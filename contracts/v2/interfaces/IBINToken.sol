// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

interface IBINToken {

    function balanceOf(address account) external returns(uint256);

    function walletMaxTokenAmount() external returns(uint256);
}