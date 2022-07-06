// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

interface IBinRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amounts);

    function swapAddBinLiquidity(uint256 returnAmount, address sender, bool isMintToken)
        external
        returns (uint256);

    function binPair() external returns(address);

    function routerSync() external;
}
