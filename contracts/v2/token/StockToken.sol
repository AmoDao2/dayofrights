// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../core/SafeOwnable.sol";
import "hardhat/console.sol";

contract StockToken is IERC20, SafeOwnable {
    string public name;
    string public symbol;
    uint8 public decimals;

    uint256 public override totalSupply;
    uint256 public remainedSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    bool public _isExcluded;
    mapping(address => bool) private minners;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _maxSupply
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        remainedSupply = _maxSupply;

        minners[msg.sender] = true;
    }

    modifier onlyMinner() {
        require(isMinner(msg.sender), "Stock: Only minner");
        _;
    }

    function excludeFrom() external onlyOwner {
        _isExcluded = true;
    }

    function includeInFrom() external onlyOwner {
        _isExcluded = false;
    }

    function isMinner(address account) public view returns (bool) {
        return minners[account];
    }

    function setMinner(address account, bool enable) external onlyOwner {
        minners[account] = enable;
    }

    function mint(address to, uint256 amount) external onlyMinner {
        require(to != address(0), "Stock: zero address");
        require(remainedSupply >= amount, "Stock: mint too much");

        remainedSupply -= amount;
        totalSupply += amount;
        balanceOf[to] += amount;

        emit Transfer(address(0), to, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(to != address(0), "Stock: zero address");
        require(balanceOf[from] >= amount, "Stock: balance not enough");
        require(_isExcluded, "Stock: not open");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    function transfer(address to, uint256 amount)
        external
        override
        returns (bool)
    {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external override returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Stock: allowance not enough");

        allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);

        return true;
    }

    function approve(address spender, uint256 amount)
        external
        override
        returns (bool)
    {
        require(spender != address(0), "Stock: zero address");

        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);

        return true;
    }
}
