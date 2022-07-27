// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "../../referral/DayOfRightsReferral.sol";
import "../../interfaces/IRouter.sol";
import "../interfaces/ISwapRouter.sol";
import "../interfaces/IBinRouter.sol";
import "../token/StockToken.sol";
import "../pool/SmartDisPatchInitializable.sol";

contract AMOPool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public dor;
    IERC20 public amo;
    IERC20 public usdt;
    StockToken public stock;
    IRouter public router;
    ISwapRouter public poolRouter;
    IBinRouter public binRouter;
    DayOfRightsReferral public user;

    uint256 public initReward;
    uint256 public startTime;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint8 public level = 0;
    uint256 public minStakeUsdt = 50 * 10**18;
    address public constant hole = 0x000000000000000000000000000000000000dEaD;

    mapping(uint8 => uint256) public levelRate;
    mapping(uint8 => uint256) public invStockRate;
    mapping(uint8 => uint256) public invUsdtRate;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint8) public userLevel;
    mapping(address => address[]) public users;
    mapping(address => uint256) public stakeUsdt;
    mapping(address => uint256) public stakeDor;
    mapping(address => uint256) public teamStock;
    mapping(address => uint8) public userNode;
    mapping(uint8 => address) public poolContract;
    mapping(address => mapping(uint8 => uint256)) public userLevelCount;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    address[] public dorPath = new address[](2);

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    uint256 public DURATION = 900 days;
    address public fundAddr;

    constructor(
        address _usdt,
        address _amo,
        address _dor,
        address _stock,
        address _swap,
        address _nftPool,
        address _fundAddr,
        uint256 _time
    ) {
        startTime = _time;
        initReward = 9000000 * 10**18;
        lastUpdateTime = startTime;
        periodFinish = lastUpdateTime;
        usdt = IERC20(_usdt);
        dor = IERC20(_dor);
        amo = IERC20(_amo);
        stock = StockToken(_stock);

        dorPath[0] = _dor;
        dorPath[1] = _usdt;

        levelRate[1] = 4;
        levelRate[2] = 3;
        levelRate[3] = 2;
        levelRate[4] = 1;

        invStockRate[1] = 50;
        invUsdtRate[1] = 5;

        router = IRouter(_swap);
        poolContract[4] = _nftPool;

        fundAddr = _fundAddr;
    }

    function setMinStakeUsdt(uint256 _num) public onlyOwner {
        minStakeUsdt = _num;
    }

    function setUserContract(address _user) public onlyOwner {
        user = DayOfRightsReferral(_user);
    }

    function setSwapRouter(address _poolRouter) public onlyOwner {
        poolRouter = ISwapRouter(_poolRouter);
    }

    function setBinRouter(address _binRouter) public onlyOwner {
        binRouter = IBinRouter(_binRouter);
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function poolInfo(address account) public view returns (uint256) {
        uint256 pool1;
        if (poolContract[1] != address(0)) {
            pool1 = SmartDisPatchInitializable(poolContract[1]).available(
                account
            );
        }
        uint256 pool2;
        if (poolContract[2] != address(0)) {
            pool2 = SmartDisPatchInitializable(poolContract[2]).available(
                account
            );
        }
        uint256 pool3;
        if (poolContract[3] != address(0)) {
            pool3 = SmartDisPatchInitializable(poolContract[3]).available(
                account
            );
        }
        return pool1.add(pool2).add(pool3);
    }

    function givePoolReward() public {
        if (poolContract[1] != address(0)) {
            SmartDisPatchInitializable(poolContract[1]).claim(msg.sender);
        }
        if (poolContract[2] != address(0)) {
            SmartDisPatchInitializable(poolContract[2]).claim(msg.sender);
        }
        if (poolContract[3] != address(0)) {
            SmartDisPatchInitializable(poolContract[3]).claim(msg.sender);
        }
    }

    function createDispatchInitialize() public onlyOwner {
        poolContract[1] = createDispatchHandle();
        poolContract[2] = createDispatchHandle();
        poolContract[3] = createDispatchHandle();
    }

    uint256 contractAmount;
    function createDispatchHandle() internal returns (address) {
        bytes memory bytecode = type(SmartDisPatchInitializable).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(address(this), contractAmount));
        address poolAddress;
        assembly {
            poolAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        SmartDisPatchInitializable(poolAddress).initialize(address(amo));
        contractAmount++;
        return poolAddress;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 usdtAmoiunt)
        external
        updateReward(msg.sender)
        checkHalve
        checkStart
    {
        require(usdtAmoiunt >= minStakeUsdt, "min usdt amount");
        require(user.referrers(_msgSender()) != address(0), "not inviter");

        uint256 dorAmount = router
        .getAmountsIn(10**18, dorPath)[0].mul(usdtAmoiunt).div(10**18);
        dor.safeTransferFrom(msg.sender, hole, dorAmount);

        //30%
        usdt.safeTransferFrom(
            msg.sender,
            address(poolRouter),
            usdtAmoiunt.mul(30).div(100)
        );
        poolRouter.swapAndLiquifyUsdtToDor(
            usdtAmoiunt.mul(30).div(100),
            address(poolRouter)
        );
        //20%
        usdt.safeTransferFrom(
            msg.sender,
            address(poolRouter),
            usdtAmoiunt.mul(20).div(100)
        );
        poolRouter.swapAndLiquifyUsdtAmo(
            usdtAmoiunt.mul(20).div(100),
            address(poolRouter)
        );
        //30%
        uint256 usdtNum = usdtAmoiunt.mul(30).div(100);
        usdt.safeTransferFrom(msg.sender, address(this), usdtNum);
        usdt.safeTransfer(address(binRouter), usdtNum);
        binRouter.swapAddBinLiquidity(usdtNum, msg.sender, true);
        //10%
        usdt.safeTransferFrom(
            msg.sender,
            fundAddr,
            usdtAmoiunt.mul(10).div(100)
        );
        //10%
        giveInvReward(msg.sender, usdtAmoiunt);

        stock.mint(address(this), usdtAmoiunt.mul(2));

        stakeUsdt[msg.sender] = stakeUsdt[msg.sender].add(usdtAmoiunt);
        stakeDor[msg.sender] = stakeDor[msg.sender].add(dorAmount);

        _totalSupply = _totalSupply.add(usdtAmoiunt.mul(2));
        _balances[msg.sender] = _balances[msg.sender].add(usdtAmoiunt.mul(2));

        updateTeam(msg.sender, usdtAmoiunt.mul(2));

        emit Staked(msg.sender, usdtAmoiunt.mul(2));
    }

    function giveInvReward(address account, uint256 amount) internal {
        address referrer = user.referrers(account);
        if (referrer != address(0) && referrer != address(user)) {
            giveInvStock(referrer, amount.mul(2), 1);
        } else {
            referrer = fundAddr;
        }
        usdt.safeTransferFrom(
            msg.sender,
            referrer,
            amount.mul(invUsdtRate[1]).div(100)
        );
    }

    function giveInvStock(
        address account,
        uint256 amount,
        uint8 index
    ) internal updateReward(account) {
        uint256 stockAmount = amount.mul(invStockRate[index]).div(100);
        stock.mint(address(this), stockAmount);
        _totalSupply = _totalSupply.add(stockAmount);
        _balances[account] = _balances[account].add(stockAmount);

        updateTeam(account, stockAmount);
    }

    function giveNodeReward(uint256 amount) internal returns (uint256) {
        uint256 rateTotal;
        for (uint8 index = 1; index != 5; index++) {
            if (levelRate[index] > 0) {
                uint256 _rate = amount.mul(levelRate[index]).div(100);
                if (poolContract[index] != address(0)) {
                    amo.safeTransfer(poolContract[index], _rate);
                } else {
                    amo.safeTransfer(hole, _rate);
                }
                rateTotal = rateTotal.add(_rate);
            }
        }
        return rateTotal;
    }

    function upgradeNode(address account, uint256 _teamStock) internal {
        (uint256 count, ) = user.recommended(account, 1, 2);
        uint8 oldLevel = userNode[account];
        uint8 newLevel = oldLevel;
        if (count >= 30 && _teamStock >= 30000 * 10**18) {
            userNode[account] = 3;
            newLevel = 3;
        } else if (count >= 20 && _teamStock >= 20000 * 10**18) {
            userNode[account] = 2;
            newLevel = 2;
        } else if (count >= 10 && _teamStock >= 10000 * 10**18) {
            userNode[account] = 1;
            newLevel = 1;
        }

        if (oldLevel != newLevel) {
            if (oldLevel != 0) {
                SmartDisPatchInitializable(poolContract[oldLevel]).withdraw(
                    account,
                    10**18
                );
            }
            if (newLevel != 0) {
                SmartDisPatchInitializable(poolContract[newLevel]).stake(
                    account,
                    10**18
                );
            }
        }
    }

    bool public isWithdraw;

    function openWithdraw() public onlyOwner {
        if(isWithdraw) {
            isWithdraw = false;
        } else {
            isWithdraw = true;
        }
    }

    function withdraw(uint256 amount)
        external
        updateReward(msg.sender)
        checkHalve
        checkStart
    {
        require(isWithdraw, "not withdraw");
        require(_balances[msg.sender] >= amount, "not amount");

        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);

        stock.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function updateTeam(address _account, uint256 _team) private {
        address _inviter = _account;
        for (uint256 i = 0; i != 4; i++) {
            if (_inviter == address(0) || address(user) == _inviter) {
                break;
            }

            teamStock[_inviter] = teamStock[_inviter].add(_team);
            upgradeNode(_inviter, teamStock[_inviter]);

            _inviter = user.referrers(_inviter);
        }
    }

    function getReward() public updateReward(msg.sender) checkHalve checkStart {
        uint256 reward = earned(msg.sender);
        if (reward <= 0) {
            return;
        }

        rewards[msg.sender] = 0;

        uint256 rateFee = giveNodeReward(reward);
        amo.transfer(msg.sender, reward.sub(rateFee));
        emit RewardPaid(msg.sender, reward.sub(rateFee));
    }

    modifier checkHalve() {
        if (block.timestamp >= periodFinish) {
            if (level >= 1) {
                initReward = 0;
                rewardRate = 0;
            } else {
                level++;
                rewardRate = initReward.div(DURATION);
            }

            if (block.timestamp > startTime.add(DURATION)) {
                startTime = startTime.add(DURATION);
            }
            periodFinish = startTime.add(DURATION);
            emit RewardAdded(initReward);
        }
        _;
    }

    modifier checkStart() {
        require(block.timestamp > startTime, "not start");
        _;
    }
}
