// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

interface ISwapRouter {

    function swapAndLiquifyUsdtAmo(uint256 contractUSDTBalance, address _liuTo)
        external;

    function swapAndLiquifyUsdtToDor(
        uint256 contractUSDTBalance,
        address _liuTo
    ) external;

    function swapUsdtForToken(
        uint256 tokenAmount,
        address path0,
        address path1,
        address _to
    ) external;

    function swapUsdtForAmo(
        uint256 tokenAmount,
        address path0,
        address _to
    ) external;

    function swapAmoForUsdt(
        uint256 tokenAmount,
        address path1,
        address _to
    ) external returns(uint[] memory amounts);
}
