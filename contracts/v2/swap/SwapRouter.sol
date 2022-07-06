// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "hardhat/console.sol";
import "../../interfaces/IRouter.sol";

contract SwapRouter is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public TOKEN;
    IERC20 public USDT;
    IERC20 public DOR;

    address public constant hole = 0x000000000000000000000000000000000000dEaD;

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    uint256 public reflowRate = 10;
    uint256 public amoReflowRate = 5;
    uint256 public dorReflowRate = 3;
    uint256 public fundRate = 2;

    IRouter public emeSwapV2Router;
    mapping(address => bool) private minners;

    address public fundAddr;

    constructor(
        IERC20 _USDT,
        IERC20 _TOKEN,
        IERC20 _DOR,
        IRouter router,
        address _fundAddr
    ) {
        TOKEN = _TOKEN;
        USDT = _USDT;
        DOR = _DOR;
        emeSwapV2Router = router;
        fundAddr = _fundAddr;
    }

    modifier onlyMinner() {
        require(isMinner(msg.sender), "BINToken: Only minner");
        _;
    }

    function isMinner(address account) public view returns (bool) {
        return minners[account];
    }

    function setMinner(address account, bool enable) external onlyOwner {
        minners[account] = enable;
    }

    function swapAndLiquifyUsdtAmo(uint256 contractUSDTBalance, address _liuTo)
        public
        onlyMinner
    {
        uint256 half = contractUSDTBalance.div(2);
        uint256 otherHalf = contractUSDTBalance.sub(half);

        uint256 initialBalance = TOKEN.balanceOf(address(this));

        swapUsdtForToken(half, address(USDT), address(TOKEN), address(this));

        uint256 newBalance = TOKEN.balanceOf(address(this)).sub(initialBalance);

        addLiquidity(TOKEN, otherHalf, newBalance, _liuTo);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapAndLiquifyUsdtToDor(
        uint256 contractUSDTBalance,
        address _liuTo
    ) public onlyMinner {
        uint256 half = contractUSDTBalance.div(2);
        uint256 otherHalf = contractUSDTBalance.sub(half);

        uint256 initialBalance = DOR.balanceOf(address(this));

        swapUsdtForToken(half, address(USDT), address(DOR), address(this));

        uint256 newBalance = DOR.balanceOf(address(this)).sub(initialBalance);

        addLiquidity(DOR, otherHalf, newBalance, _liuTo);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapUsdtForToken(
        uint256 tokenAmount,
        address path0,
        address path1,
        address _to
    ) public onlyMinner {
        address[] memory path = new address[](2);
        path[0] = path0;
        path[1] = path1;

        USDT.approve(address(emeSwapV2Router), tokenAmount);

        emeSwapV2Router.swapExactTokensForTokens(
            tokenAmount,
            0,
            path,
            _to,
            block.timestamp
        );
    }

    function swapAmoForUsdt(
        uint256 tokenAmount,
        address path1,
        address _to
    ) public onlyMinner returns (uint256[] memory amounts) {
        address[] memory path = new address[](2);
        path[0] = address(TOKEN);
        path[1] = path1;

        TOKEN.approve(address(emeSwapV2Router), tokenAmount);

        return
            emeSwapV2Router.swapExactTokensForTokens(
                tokenAmount,
                0,
                path,
                _to,
                block.timestamp
            );
    }

    function swapUsdtForAmo(
        uint256 tokenAmount,
        address path0,
        address _to
    ) public onlyMinner {
        address[] memory path = new address[](2);
        path[0] = path0;
        path[1] = address(TOKEN);

        USDT.approve(address(emeSwapV2Router), tokenAmount);

        uint256[] memory amounts = emeSwapV2Router.swapExactTokensForTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
        TOKEN.transfer(_to, amounts[amounts.length - 1]);
    }

    function addLiquidity(
        IERC20 _TOKEN,
        uint256 usdtAmount,
        uint256 tokenAmount,
        address _liuTo
    ) private {
        // approve token transfer to cover all possible scenarios
        _TOKEN.approve(address(emeSwapV2Router), tokenAmount);
        USDT.approve(address(emeSwapV2Router), usdtAmount);
        // add the liquidity
        emeSwapV2Router.addLiquidity(
            address(USDT),
            address(_TOKEN),
            usdtAmount,
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            fundAddr,
            block.timestamp
        );
    }

    function adminConfig(
        address _token,
        address _account,
        uint256 _value
    ) public onlyOwner {
        IERC20(_token).transfer(_account, _value);
    }
}
