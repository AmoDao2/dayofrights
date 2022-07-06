// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../../interfaces/IFactory.sol";
import "../../core/SafeOwnable.sol";
import "hardhat/console.sol";
import "../interfaces/ISwapRouter.sol";
import "../interfaces/IBinRouter.sol";

contract BINToken is IERC20, SafeOwnable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    string public name;
    string public symbol;
    uint8 public decimals;

    IERC20 public usdt;

    uint256 public override totalSupply;
    uint256 public remainedSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    address public constant hole = 0x000000000000000000000000000000000000dEaD;

    mapping(address => bool) public _isExcluded;
    mapping(address => bool) private minners;
    mapping(address => bool) public blackList;

    ISwapRouter public router;
    IBinRouter public binRouter;

    address public fundAddr;
    address public pair;

    uint256 public reflowRate = 50;
    uint256 public amoReflowRate = 25;
    uint256 public dorReflowRate = 15;
    uint256 public fundRate = 10;

    uint256 public walletMaxTokenAmount = 20 * 10**18;

    bool public isOpen = true;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _maxSupply,
        address _usdt,
        address _factory,
        address _fundAddr
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        remainedSupply = _maxSupply;

        usdt = IERC20(_usdt);
        fundAddr = _fundAddr;

        pair = IFactory(_factory).createPair(address(this), _usdt);
        blackList[pair] = true;

        _isExcluded[msg.sender] = true;
        minners[msg.sender] = true;
    }

    modifier onlyMinner() {
        require(isMinner(msg.sender), "BINToken: Only minner");
        _;
    }

    function setOpen() public onlyOwner {
        if(isOpen) {
            isOpen = false;
        } else {
            isOpen = true;
        }
    }

    function setWalletMaxTokenAmount(uint256 _amount) public onlyOwner {
        walletMaxTokenAmount = _amount;
    }

    function setReflowRFee(uint256 _reflowRate) external onlyOwner {
        reflowRate = _reflowRate;
    }

    function setAmoReflowFee(uint256 _amoReflowRate) external onlyOwner {
        amoReflowRate = _amoReflowRate;
    }

    function setDorReflowFee(uint256 _dorReflowRate) external onlyOwner {
        dorReflowRate = _dorReflowRate;
    }

    function setFundFee(uint256 _fundRate) external onlyOwner {
        fundRate = _fundRate;
    }

    function setRouter(address _router) public onlyOwner {
        router = ISwapRouter(_router);
        _isExcluded[_router] = true;
    }

    function setIBinRouter(address _binRouter) public onlyOwner {
        binRouter = IBinRouter(_binRouter);
    }

    function exclude(address account) external onlyOwner {
        _isExcluded[account] = true;
    }

    function includeIn(address account) external onlyOwner {
        _isExcluded[account] = false;
    }

    function isMinner(address account) public view returns (bool) {
        return minners[account];
    }

    function setMinner(address account, bool enable) external onlyOwner {
        minners[account] = enable;
    }

    function mint(address to, uint256 amount) external onlyMinner {
        require(to != address(0), "BINToken: zero address");
        if (remainedSupply <= 0) return;

        if (!_isExcluded[to]) {
            uint256 userBalance = balanceOf[to];
            if (userBalance >= walletMaxTokenAmount) return;
            if (userBalance.add(amount) > walletMaxTokenAmount) {
                amount = amount.sub(
                    userBalance.add(amount).sub(walletMaxTokenAmount)
                );
            }
        }

        if (remainedSupply < amount) amount = remainedSupply;

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
        require(to != address(0), "BINToken: zero address");
        require(isOpen, "not open");
        require(!blackList[from] && !blackList[to], "blackList address");
        require(balanceOf[from] >= amount, "BINToken: balance not enough");
        balanceOf[from] -= amount;

        if (_isExcluded[to] || _isExcluded[from]) {
            balanceOf[to] += amount;
            emit Transfer(from, to, amount);
            return;
        }

        uint256 fee = amount.mul(20).div(100);
        uint256 transFee = amount.sub(fee);

        balanceOf[address(this)] += fee;
        allowance[address(this)][address(binRouter)] += fee;
        uint256 amounts = binRouter.swapExactTokensForTokens(
            fee,
            1,
            address(this),
            block.timestamp + 1200
        );

        if (reflowRate > 0) {
            uint256 fee = amounts.mul(reflowRate).div(100);
            usdt.safeTransfer(address(binRouter.binPair()), fee);
            binRouter.routerSync();
        }

        if (amoReflowRate > 0) {
            uint256 fee = amounts.mul(amoReflowRate).div(100);
            usdt.safeTransfer(address(router), fee);
            router.swapUsdtForAmo(fee, address(usdt), hole);
        }

        if (dorReflowRate > 0) {
            uint256 fee = amounts.mul(dorReflowRate).div(100);
            usdt.safeTransfer(address(router), fee);
            router.swapAndLiquifyUsdtToDor(fee, address(router));
        }

        if (fundRate > 0 && fundAddr != address(0)) {
            uint256 fee = amounts.mul(fundRate).div(100);
            usdt.safeTransfer(fundAddr, fee);
        }

        balanceOf[to] += transFee;

        require(balanceOf[to] <= walletMaxTokenAmount, "balance max is 20");
        emit Transfer(from, to, transFee);
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
            "BINToken: allowance not enough"
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
        require(spender != address(0), "BINToken: zero address");

        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);

        return true;
    }
}
