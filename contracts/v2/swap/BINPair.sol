// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "../libraries/UQ112x112.sol";
import "../libraries/TransferHelper.sol";
import "../token/BINERC20.sol";

contract BINPair is BINERC20 {
    using SafeMath for uint256;
    using UQ112x112 for uint224;

    address public constant hole = 0x000000000000000000000000000000000000dEaD;

    uint256 constant SWAP_FEE = 3;
    uint256 constant SWAP_FEE_BASE = 1000;
    uint256 constant SWAP_FEE_LP = 2;

    bytes4 private constant SELECTOR =
        bytes4(keccak256(bytes("transfer(address,uint256)")));

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0; // uses single storage slot, accessible via getReserves
    uint112 private reserve1; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() {
        factory = msg.sender;
    }

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "SWAP: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    address public owner;
    modifier pairOwner() {
        require(owner == msg.sender, "SWAP: EXPIRED");
        _;
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(SELECTOR, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "SWAP: TRANSFER_FAILED"
        );
    }

    // called once by the factory at time of deployment
    function initialize(
        address _token0,
        address _token1,
        uint256 _amount0,
        uint256 _amount1,
        address _owner
    ) external {
        require(factory == msg.sender, "SWAP: EXPIRED");
        token0 = _token0;
        token1 = _token1;
        owner = _owner;

        _update(_amount0, _amount1, reserve0, reserve1);
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private {
        require(
            balance0 <= uint112(-1) && balance1 <= uint112(-1),
            "SWAP: OVERFLOW"
        );

        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast +=
                uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) *
                timeElapsed;
            price1CumulativeLast +=
                uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) *
                timeElapsed;
        }

        if (balance0 > _reserve0 && _reserve1 > balance1) {
            uint256 bal0 = (balance0 - _reserve0) * 2;
            require(balance0 > bal0, "SWAP: balance0 EX");
            _safeTransfer(token0, hole, bal0);
            balance0 = balance0 - bal0;
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) public lock {
        require(factory == msg.sender, "SWAP: EXPIRED");
        require(
            amount0Out > 0 || amount1Out > 0,
            "SWAP: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        require(
            amount0Out < _reserve0 && amount1Out < _reserve1,
            "SWAP: INSUFFICIENT_LIQUIDITY"
        );

        uint256 balance0;
        uint256 balance1;
        {
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, "SWAP: INVALID_TO");
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out);
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out);
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out
            ? balance0 - (_reserve0 - amount0Out)
            : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out
            ? balance1 - (_reserve1 - amount1Out)
            : 0;
        require(
            amount0In > 0 || amount1In > 0,
            "SWAP: INSUFFICIENT_INPUT_AMOUNT"
        );
        {
            uint256 balance0Adjusted = balance0.mul(1000).sub(
                amount0In.mul(SWAP_FEE)
            );
            uint256 balance1Adjusted = balance1.mul(1000).sub(
                amount1In.mul(SWAP_FEE)
            );
            require(
                balance0Adjusted.mul(balance1Adjusted) >=
                    uint256(_reserve0).mul(_reserve1).mul(1000**2),
                "SWAP: K"
            );
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function skim(address to) external lock pairOwner {
        address _token0 = token0;
        address _token1 = token1;
        _safeTransfer(
            _token0,
            to,
            IERC20(_token0).balanceOf(address(this)).sub(reserve0)
        );
        _safeTransfer(
            _token1,
            to,
            IERC20(_token1).balanceOf(address(this)).sub(reserve1)
        );
    }

    function sync() external lock pairOwner {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }

    function _updateSync() external lock {
        require(factory == msg.sender, "SWAP: EXPIRED");
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast +=
                uint256(UQ112x112.encode(reserve1).uqdiv(reserve0)) *
                timeElapsed;
            price1CumulativeLast +=
                uint256(UQ112x112.encode(reserve0).uqdiv(reserve1)) *
                timeElapsed;
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    function getReserves()
        public
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function getAmountOut(uint256 amountIn)
        public
        view
        returns (uint256 amountOut)
    {
        (uint256 reserveIn, uint256 reserveOut, ) = getReserves();
        require(amountIn > 0, "Library: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 amountInWithFee = amountIn.mul(SWAP_FEE_BASE.sub(SWAP_FEE));
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(SWAP_FEE_BASE).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    function getAmountIn(uint256 amountOut)
        public
        view
        returns (uint256 amountIn)
    {
        (uint256 reserveIn, uint256 reserveOut, ) = getReserves();
        require(amountOut > 0, "EMELibrary: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "EMELibrary: INSUFFICIENT_LIQUIDITY"
        );
        uint256 numerator = reserveIn.mul(amountOut).mul(SWAP_FEE_BASE);
        uint256 denominator = reserveOut.sub(amountOut).mul(
            SWAP_FEE_BASE.sub(SWAP_FEE)
        );
        amountIn = (numerator / denominator).add(1);
    }
}
