// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interfaces/ISwapRouter.sol";
import "../interfaces/IBinRouter.sol";
import "../../interfaces/IFactory.sol";
import "../../core/SafeOwnable.sol";
import "hardhat/console.sol";
import "../swap/SwapRouter.sol";
import "../pool/SmartDisPatchInitializable.sol";

contract AMOToken is IERC20, SafeOwnable {
    using SafeMath for uint256;

    string public name;
    string public symbol;
    uint8 public decimals;

    uint256 public override totalSupply;
    uint256 public remainedSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    address public constant hole = 0x000000000000000000000000000000000000dEaD;

    mapping(address => bool) private minners;
    mapping(address => bool) public blackList;
    mapping(address => bool) public whiteList;

    uint256 public binRate = 4;
    uint256 public holeRate = 2;
    uint256 public poolRate = 2;

    address public poolContract;
    ISwapRouter public swapRouter;
    IBinRouter public binRouter;
    address public pair;
    address public usdt;

    bool public isOpen = true;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _maxSupply,
        address _factory,
        address _usdt
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        remainedSupply = _maxSupply;
        usdt = _usdt;

        pair = IFactory(_factory).createPair(address(this), _usdt);
        blackList[pair] = true;

        minners[msg.sender] = true;
        whiteList[msg.sender] = true;
    }

    modifier onlyMinner() {
        require(isMinner(msg.sender), "MFToken: Only minner");
        _;
    }

    function setOpen() public onlyOwner {
        if(isOpen) {
            isOpen = false;
        } else {
            isOpen = true;
        }
    }

    function setPoolContract(address _pool) public onlyOwner {
        poolContract = _pool;
        whiteList[_pool] = true;
    }

    function setSwapRouter(address _swapRouter) public onlyOwner {
        swapRouter = ISwapRouter(_swapRouter);
        whiteList[_swapRouter] = true;
        allowance[address(this)][_swapRouter] = uint256(-1);
    }

    function setIBinRouter(address _swapRouter) public onlyOwner {
        binRouter = IBinRouter(_swapRouter);
    }

    function excludeBlackList(address account) external onlyOwner {
        blackList[account] = true;
    }

    function includeInBlackList(address account) external onlyOwner {
        blackList[account] = false;
    }

    function excludeWhiteList(address account) external onlyOwner {
        whiteList[account] = true;
    }

    function includeInWhiteList(address account) external onlyOwner {
        whiteList[account] = false;
    }

    function isMinner(address account) public view returns (bool) {
        return minners[account];
    }

    function setMinner(address account, bool enable) external onlyOwner {
        minners[account] = enable;
    }

    function mint(address to, uint256 amount) external onlyMinner {
        require(to != address(0), "MFToken: zero address");
        require(remainedSupply >= amount, "MFToken: mint too much");

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
        require(isOpen, "not open");
        require(to != address(0), "AMOToken: zero address");
        require(balanceOf[from] >= amount, "AMOToken: balance not enough");
        if (blackList[from] || blackList[to]) {
            require(
                (blackList[from] && whiteList[to]) ||
                    (blackList[to] && whiteList[from]),
                "AMOToken: from or to is blackList"
            );
        }
        if (!whiteList[from] && !whiteList[to]) {
            balanceOf[from] -= amount;
            amount = transferFee(from, amount);
            balanceOf[to] += amount;
            emit Transfer(from, to, amount);
        } else {
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
            emit Transfer(from, to, amount);
        }
    }

    function transferFee(address from, uint256 tokenAmount) internal returns (uint256) {
        uint256 returnAmountB = tokenAmount;
        if (binRate > 0) {
            uint256 fee = tokenAmount.mul(binRate).div(100);
            balanceOf[address(swapRouter)] += fee;
            uint[] memory amounts = swapRouter.swapAmoForUsdt(fee, usdt, address(binRouter));
            binRouter.swapAddBinLiquidity(amounts[amounts.length - 1], address(0), false);
            returnAmountB = returnAmountB.sub(fee);
        }
        if (holeRate > 0) {
            uint256 fee = tokenAmount.mul(holeRate).div(100);
            balanceOf[hole] += fee;
            emit Transfer(from, hole, fee);
            returnAmountB = returnAmountB.sub(fee);
        }
        if (poolRate > 0) {
            uint256 fee = tokenAmount.mul(poolRate).div(100);
            balanceOf[poolContract] += fee;
            emit Transfer(from, poolContract, fee);
            returnAmountB = returnAmountB.sub(fee);
        }

        return returnAmountB;
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
        require(
            allowance[from][msg.sender] >= amount,
            "MFToken: allowance not enough"
        );

        allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);

        return true;
    }

    function approve(address spender, uint256 amount)
        external
        override
        returns (bool)
    {
        require(spender != address(0), "MFToken: zero address");

        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);

        return true;
    }
}
