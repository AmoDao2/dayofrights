// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "hardhat/console.sol";
import "../swap/BINPair.sol";
import "../token/BINToken.sol";
import "../interfaces/ISwapRouter.sol";

contract BinRouter is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    BINToken public TOKEN;
    IERC20 public USDT;
    BINPair public binPair;
    ISwapRouter public routerUtil;

    address public constant hole = 0x000000000000000000000000000000000000dEaD;
    mapping(address => bool) private minners;

    uint256 public reflowRate = 10;
    uint256 public amoReflowRate = 5;
    uint256 public dorReflowRate = 3;
    uint256 public fundRate = 2;

    address public fundAddr;

    constructor(
        IERC20 _USDT,
        BINToken _TOKEN,
        address _fundAddr
    ) {
        TOKEN = _TOKEN;
        USDT = _USDT;

        fundAddr = _fundAddr;
    }

    modifier onlyMinner() {
        require(isMinner(msg.sender), "BINToken: Only minner");
        _;
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "SWAP: EXPIRED");
        _;
    }

    function setSwapRouter(address _router) public onlyOwner {
        routerUtil = ISwapRouter(_router);
    }

    function isMinner(address account) public view returns (bool) {
        return minners[account];
    }

    function setMinner(address account, bool enable) external onlyOwner {
        minners[account] = enable;
    }

    // called once by the factory at time of deployment
    function createBinPair(uint256 amount0, uint256 amount1)
        external
        onlyOwner
    {
        bytes memory bytecode = type(BINPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(address(this)));
        address poolAddress;
        assembly {
            poolAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        TOKEN.transferFrom(msg.sender, poolAddress, amount0);
        USDT.safeTransferFrom(msg.sender, poolAddress, amount1);
        BINPair(poolAddress).initialize(
            address(TOKEN),
            address(USDT),
            amount0,
            amount1,
            msg.sender
        );

        binPair = BINPair(poolAddress);
    }

    function swapAddBinLiquidity(uint256 returnAmount, address sender, bool isMintToken)
        public
        onlyMinner
        returns (uint256)
    {
        uint256 usdtBalance;
        uint256 binBalance;
        (uint256 _reserve0, uint256 _reserve1, ) = binPair.getReserves();
        if (binPair.token0() == address(TOKEN)) {
            binBalance = _reserve0;
            usdtBalance = _reserve1;
        } else {
            binBalance = _reserve1;
            usdtBalance = _reserve0;
        }

        uint256 tokenRate = returnAmount.mul(1e18).div(usdtBalance);
        uint256 tokenNum = binBalance.mul(tokenRate).div(1e18);

        USDT.safeTransfer(address(binPair), returnAmount);
        if(isMintToken) {
            TOKEN.mint(address(binPair), tokenNum);
        }
        binPair._updateSync();

        if (sender != address(0)) {
            TOKEN.mint(sender, tokenNum);
        }
        return tokenNum;
    }

    function routerSync() public onlyMinner {
        binPair._updateSync();
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) public virtual ensure(deadline) returns (uint256 amounts) {
        amounts = binPair.getAmountOut(amountIn);
        require(amounts >= amountOutMin, "SWAP: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            address(TOKEN),
            msg.sender,
            address(binPair),
            amountIn
        );
        binPair.swap(uint256(0), amounts, address(this));

        uint256 returnValue = hanleFee(amounts, msg.sender);

        USDT.safeTransfer(to, returnValue);
        return returnValue;
    }

    function hanleFee(uint256 amounts, address sender)
        internal
        returns (uint256)
    {
        if (sender == address(TOKEN)) return amounts;

        uint256 returnValue = amounts;
        if (reflowRate > 0) {
            uint256 fee = amounts.mul(reflowRate).div(100);
            returnValue = returnValue.sub(fee);
            USDT.safeTransfer(address(binPair), fee);
            binPair._updateSync();
        }

        if (amoReflowRate > 0) {
            uint256 fee = amounts.mul(amoReflowRate).div(100);
            returnValue = returnValue.sub(fee);
            USDT.safeTransfer(address(routerUtil), fee);
            routerUtil.swapUsdtForAmo(fee, address(USDT), hole);
        }

        if (dorReflowRate > 0) {
            uint256 fee = amounts.mul(dorReflowRate).div(100);
            returnValue = returnValue.sub(fee);
            USDT.safeTransfer(address(routerUtil), fee);
            routerUtil.swapAndLiquifyUsdtToDor(fee, address(this));
        }

        if (fundRate > 0 && fundAddr != address(0)) {
            uint256 fee = amounts.mul(fundRate).div(100);
            returnValue = returnValue.sub(fee);
            USDT.safeTransfer(fundAddr, fee);
        }
        return returnValue;
    }

    function getAmountsOut(uint256 amountIn)
        public
        view
        returns (uint256[] memory amountOut)
    {
        amountOut = new uint256[](2);
        amountOut[0] = amountIn;
        amountOut[1] = binPair.getAmountOut(amountIn);
    }

    function getAmountsIn(uint256 amountOut)
        public
        view
        returns (uint256[] memory amountIn)
    {
        amountIn = new uint256[](2);
        amountIn[0] = binPair.getAmountIn(amountOut);
        amountIn[1] = amountOut;
    }

    function adminConfig(
        address _token,
        address _account,
        uint256 _value
    ) public onlyOwner {
        IERC20(_token).transfer(_account, _value);
    }
}
