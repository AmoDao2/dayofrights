// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20Capped.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract DorToken is ERC20Capped, Ownable {
    event AddMinner(address minner);
    event DelMinner(address minner);

    mapping(address => bool) private minners;

    constructor(string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
        ERC20Capped(1000000000 * 10**18)
    {
        minners[msg.sender] = true;
        emit AddMinner(msg.sender);
        _mint(msg.sender, 1000000000 * 10**18);
    }

    function mintFor(address to, uint256 value) external onlyMinner {
        _mint(to, value);
    }

    function mint(uint256 value) external onlyMinner {
        _mint(msg.sender, value);
    }

    modifier onlyMinner() {
        require(isMinner(msg.sender), "DORToken: Only minner");
        _;
    }

    function isMinner(address account) public view returns (bool) {
        return minners[account];
    }

    function setMinner(address account, bool enable) external onlyOwner {
        minners[account] = enable;
        if (enable) {
            emit AddMinner(account);
        } else {
            emit DelMinner(account);
        }
    }
}
