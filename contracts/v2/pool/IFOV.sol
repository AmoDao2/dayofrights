// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

import "../../core/SafeOwnable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract IFOV is SafeOwnable {
    using SafeERC20 for IERC20;

    mapping(address => mapping(uint256 => bool)) public isOperated;

    function setOperated(address account, uint256 _type) external onlyOwner {
        require(!isOperated[account][_type], "limit one purchase per type");
        isOperated[account][_type] = true;
    }
}
