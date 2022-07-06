// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../libraries/Library.sol";
import "../libraries/TransferHelper.sol";
import "../../core/SafeOwnable.sol";
import "../pool/LPPool.sol";
import "../interfaces/IBinRouter.sol";

contract AMORouter is SafeOwnable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Withdraw(address indexed user, uint256 amount);

    address public immutable factory;
    address public immutable usdt;
    address public immutable token;
    address public immutable pair;

    address public constant hole = 0x000000000000000000000000000000000000dEaD;

    mapping(address => uint256) public balance;

    address public poolContract;
    IBinRouter public binRouter;

    constructor(
        address _factory,
        address _usdt,
        address _token
    ) {
        factory = _factory;
        usdt = _usdt;
        token = _token;

        address _mfPair = IFactory(_factory).getPair(_token, _usdt);
        if (_mfPair == address(0)) {
            _mfPair = IFactory(_factory).createPair(_token, _usdt);
        }
        pair = _mfPair;
    }

    function setPoolContract(address _pool) public onlyOwner {
        poolContract = _pool;
    }

    function setIBinRouter(address _binRouter) public onlyOwner {
        binRouter = IBinRouter(_binRouter);
    }

    // **** ADD LIQUIDITY ****
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        public
        virtual
        ensure(deadline)
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        (amountA, amountB) = _addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );
        TransferHelper.safeTransferFrom(
            tokenA,
            msg.sender,
            address(this),
            amountA
        );
        TransferHelper.safeTransferFrom(
            tokenB,
            msg.sender,
            address(this),
            amountB
        );

        if (tokenA == usdt) {
            (amountA, amountB) = swapAddLiquidity(msg.sender, amountA, amountB);
            TransferHelper.safeTransfer(tokenA, pair, amountA);
            TransferHelper.safeTransfer(tokenB, pair, amountB);
        } else {
            (amountB, amountA) = swapAddLiquidity(msg.sender, amountB, amountA);
            TransferHelper.safeTransfer(tokenA, pair, amountA);
            TransferHelper.safeTransfer(tokenB, pair, amountB);
        }

        liquidity = IPair(pair).mint(address(this));

        LPPool(poolContract).stake(to, liquidity);
        balance[to] = balance[to] + liquidity;
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        public
        virtual
        ensure(deadline)
        returns (uint256 amountA, uint256 amountB)
    {
        require(balance[to] >= liquidity, "not liquidity");
        balance[to] = balance[to].sub(liquidity);
        TransferHelper.safeTransfer(pair, pair, liquidity);

        (amountA, amountB) = _removeLiquidity(
            tokenA,
            tokenB,
            amountAMin,
            amountBMin,
            to,
            pair
        );

        LPPool(poolContract).withdraw(to, liquidity);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual returns (uint256 amountA, uint256 amountB) {
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(
            tokenA,
            tokenB,
            liquidity,
            amountAMin,
            amountBMin,
            to,
            deadline
        );
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (IFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = Library.getReserves(
            factory,
            tokenA,
            tokenB
        );
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = Library.quote(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                require(
                    amountBOptimal >= amountBMin,
                    "EMERouter: INSUFFICIENT_B_AMOUNT"
                );
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = Library.quote(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                assert(amountAOptimal <= amountADesired);
                require(
                    amountAOptimal >= amountAMin,
                    "EMERouter: INSUFFICIENT_A_AMOUNT"
                );
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function _removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        address pair
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        (uint256 amount0, uint256 amount1) = IPair(pair).burn(address(this));
        (address token0, ) = Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0
            ? (amount0, amount1)
            : (amount1, amount0);

        if (tokenA == usdt) {
            (amountA, amountB) = swapRemoveLiquidity(amountA, amountB);
            TransferHelper.safeTransfer(tokenA, to, amountA);
            TransferHelper.safeTransfer(tokenB, to, amountB);
        } else {
            (amountB, amountA) = swapRemoveLiquidity(amountB, amountA);
            TransferHelper.safeTransfer(tokenA, to, amountA);
            TransferHelper.safeTransfer(tokenB, to, amountB);
        }
        require(amountA >= amountAMin, "EMERouter: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "EMERouter: INSUFFICIENT_B_AMOUNT");
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2
                ? Library.pairFor(factory, output, path[i + 2])
                : _to;
            IPair(Library.pairFor(factory, input, output)).swap(
                amount0Out,
                amount1Out,
                to,
                new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual ensure(deadline) returns (uint256[] memory amounts) {
        amounts = Library.getAmountsOut(factory, amountIn, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "EMERouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );

        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            address(this),
            amounts[0]
        );

        if (path[0] == usdt) {
            uint256 returnAmount = swapToToken(amounts[0]);
            amounts = Library.getAmountsOut(factory, returnAmount, path);
            TransferHelper.safeTransfer(path[0], pair, amounts[0]);
            _swap(amounts, path, address(this));
            TransferHelper.safeTransfer(
                path[path.length - 1],
                to,
                amounts[amounts.length - 1]
            );
        } else {
            uint256 returnAmount = swapToUsdt(amounts[0], path, deadline);
            amounts = Library.getAmountsOut(factory, returnAmount, path);
            TransferHelper.safeTransfer(path[0], pair, returnAmount);
            _swap(amounts, path, address(this));

            TransferHelper.safeTransfer(
                path[path.length - 1],
                to,
                amounts[amounts.length - 1]
            );
        }
    }

    function swapExactTokensForUsdt(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) internal virtual ensure(deadline) returns (uint256[] memory amounts) {
        amounts = Library.getAmountsOut(factory, amountIn, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "EMERouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );

        TransferHelper.safeTransfer(path[0], pair, amounts[0]);
        _swap(amounts, path, to);
    }

    uint256 public swapBuyRate = 8;

    function swapToToken(uint256 amount) internal returns (uint256) {
        if (swapBuyRate <= 0) return amount;
        uint256 returnAmount = amount;
        uint256 fee = returnAmount.mul(swapBuyRate).div(100);
        IERC20(usdt).safeTransfer(address(binRouter), fee);
        binRouter.swapAddBinLiquidity(fee, poolContract, true);
        return returnAmount.sub(fee);
    }

    uint256 public swapSellBinLiquidityRate = 4;
    uint256 public swapSellHoleRate = 2;
    uint256 public swapSellPoolRate = 2;

    function swapToUsdt(uint256 amount, address[] calldata path, uint256 deadline)
        internal
        returns (uint256)
    {
        uint256 tokenAmount = amount;
        if (swapSellBinLiquidityRate > 0) {
            uint256 fee = amount.mul(swapSellBinLiquidityRate).div(100);
            tokenAmount = tokenAmount.sub(fee);
            uint256[] memory amounts = swapExactTokensForUsdt(
                fee,
                1,
                path,
                address(binRouter),
                deadline
            );
            binRouter.swapAddBinLiquidity(
                amounts[amounts.length - 1],
                address(0),
                false
            );
        }

        if (swapSellHoleRate > 0) {
            uint256 fee = amount.mul(swapSellHoleRate).div(100);
            IERC20(token).safeTransfer(hole, fee);
            tokenAmount = tokenAmount.sub(fee);
        }

        if (swapSellPoolRate > 0) {
            uint256 fee = amount.mul(swapSellPoolRate).div(100);
            IERC20(token).safeTransfer(poolContract, fee);
            tokenAmount = tokenAmount.sub(fee);
        }
        return tokenAmount;
    }

    uint256 public swapAddLiquidityBinLiquidityRate = 8;

    function swapAddLiquidity(
        address sender,
        uint256 amount,
        uint256 tokenAmount
    ) internal returns (uint256, uint256) {
        if (swapAddLiquidityBinLiquidityRate <= 0) return (amount, tokenAmount);
        uint256 returnAmount = amount;
        uint256 fee = returnAmount.mul(swapAddLiquidityBinLiquidityRate).div(
            100
        );
        uint256 tokenFee = tokenAmount
            .mul(swapAddLiquidityBinLiquidityRate)
            .div(100);
        IERC20(usdt).safeTransfer(address(binRouter), fee);
        binRouter.swapAddBinLiquidity(fee, sender, true);
        returnAmount = returnAmount.sub(fee);

        uint256 tokenValue = tokenAmount.sub(tokenFee);
        return (returnAmount, tokenValue);
    }

    uint256 public swapRemoveLiquidityBinLiquidityRate = 4;
    uint256 public swapRemoveLiquidityHoleRate = 2;
    uint256 public swapRemoveLiquidityPoolRate = 2;

    function swapRemoveLiquidity(uint256 usdtAmount, uint256 tokenAmount)
        internal
        returns (uint256, uint256)
    {
        uint256 returnAmount = usdtAmount;
        uint256 returnAmountB = tokenAmount;
        if (swapRemoveLiquidityBinLiquidityRate > 0) {
            uint256 fee = returnAmount
                .mul(swapRemoveLiquidityBinLiquidityRate)
                .div(100);
            IERC20(usdt).safeTransfer(address(binRouter), fee);
            binRouter.swapAddBinLiquidity(fee, address(0), false);
            returnAmount = returnAmount.sub(fee);
        }
        if (swapRemoveLiquidityHoleRate > 0) {
            uint256 fee = tokenAmount.mul(swapRemoveLiquidityHoleRate).div(100);
            IERC20(token).safeTransfer(hole, fee);
            returnAmountB = returnAmountB.sub(fee);
        }
        //进行平分AMO
        if (swapRemoveLiquidityPoolRate > 0) {
            uint256 fee = tokenAmount.mul(swapRemoveLiquidityPoolRate).div(100);
            IERC20(token).safeTransfer(poolContract, fee);
            returnAmountB = returnAmountB.sub(fee);
        }

        return (returnAmount, returnAmountB);
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "EMERouter: EXPIRED");
        _;
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure virtual returns (uint256 amountB) {
        return Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual returns (uint256 amountOut) {
        return Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual returns (uint256 amountIn) {
        return Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        virtual
        returns (uint256[] memory amounts)
    {
        return Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path)
        public
        view
        virtual
        returns (uint256[] memory amounts)
    {
        return Library.getAmountsIn(factory, amountOut, path);
    }
}
