// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./SafeCastUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";

interface IUniswapV2Pair {
    function totalSupply() external view returns (uint);
    function token0() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IMiniChefV2 {
    function userInfo(uint256 _pid, address _user) external view returns (uint256 amount, int256 rewardDebt);
}

interface IHarvester {
    function getUserGlobalDeposit(address _user) external view returns (uint256 globalDepositAmount, uint256 globalLockLpAmount, uint256 globalLpAmount, int256 globalRewardDebt);
}

interface IHarvesterFactory {
    function getAllHarvesters() external view returns (address[] memory);
}

contract TreasureDAO is ERC20Upgradeable, OwnableUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;

    enum Lock { 
        UNKNOWN,
        TWO_WEEKS
    }

    struct DepositInfo {
        uint256 depositAmount;
        uint96 lockedUntil;
        Lock lock;
    }
    
    event Deposit(address indexed user, uint256 indexed index, uint256 amount, Lock lock);
    event Withdraw(address indexed user, uint256 indexed index, uint256 amount);

    uint256 public constant PID = 13;

    // Magic token addr
    IERC20Upgradeable public magic;
    IUniswapV2Pair public sushiLP;
    IMiniChefV2 public miniChefV2;
    IHarvesterFactory public harvesterFactory;

    /**
     * @notice Used to disable the lock for all deposits
     */
    bool public unlockAll;

    /// @notice user => depositId => DepositInfo
    mapping (address => mapping (uint256 => DepositInfo)) public depositInfo;
    /// @notice user => depositId[]
    mapping (address => EnumerableSetUpgradeable.UintSet) private allUserDepositIds;
    /// @notice user => deposit index
    mapping (address => uint256) public currentId;


    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @dev Disables the ability for impl contracts that are used for strictly logic
    /// From being initialized and potentially hijacked
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _magic, 
        address _sushiLP, 
        address _miniChefV2, 
        address _harvesterFactory
    ) public initializer {
        __Ownable_init();
        __ERC20_init("Treasure DAO Governance", "gMAGIC");
        magic = IERC20Upgradeable(_magic);
        sushiLP = IUniswapV2Pair(_sushiLP);
        miniChefV2 = IMiniChefV2(_miniChefV2);
        harvesterFactory = IHarvesterFactory(_harvesterFactory);
    }

    function totalSupply() public pure override returns (uint256) {
        return 0;
    }

    function balanceOf(address _account) public view override returns (uint256) {
        return getStakedBalance(_account) + getLPBalance(_account) + getHarvesterBalance(_account);
    }

    function getStakedBalance(address _account) public view returns (uint256 userBalance_) {
        uint256[] memory allDeposits = getAllUserDepositIds(_account);
        uint256 len = allDeposits.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 depositId = allDeposits[i];
            userBalance_ += depositInfo[_account][depositId].depositAmount;
        }
    }

    function getLPBalance(address _account) public view returns (uint256) {
        (uint256 liquidity, ) = miniChefV2.userInfo(PID, _account);
        (uint112 _reserve0, uint112 _reserve1,) = sushiLP.getReserves();

        if (address(magic) == sushiLP.token0()) {
            return _reserve0 * liquidity / sushiLP.totalSupply();
        } else {
            return _reserve1 * liquidity / sushiLP.totalSupply();
        }
    }

    function getHarvesterBalance(address _account) public view returns (uint256 harvesterBalance) {
        address[] memory harvesters = harvesterFactory.getAllHarvesters();
        uint256 len = harvesters.length;
        for (uint256 i = 0; i < len; i++) {
            (uint256 globalDepositAmount,,,) = IHarvester(harvesters[i]).getUserGlobalDeposit(_account);
            harvesterBalance += globalDepositAmount;
        }
    }

    function deposit(uint256 _amount) public {
        require(allUserDepositIds[msg.sender].length() < 3000, "Max deposits number reached");

        (DepositInfo storage depositCur, uint256 depositId) = _addDeposit(msg.sender);

        depositCur.depositAmount = _amount;
        depositCur.lockedUntil = uint96(block.timestamp + 14 days);
        depositCur.lock = Lock.TWO_WEEKS;

        magic.safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, depositId, _amount, Lock.TWO_WEEKS);
    }

    function withdraw(uint256 _depositId, uint256 _amount) external {
        require(_withdraw(_depositId, _amount), "Could not withdraw given deposit");
    }

    function withdrawAll() public virtual {
        uint256[] memory depositIds = allUserDepositIds[msg.sender].values();
        for (uint256 i = 0; i < depositIds.length; i++) {
            _withdraw(depositIds[i], type(uint256).max);
        }
    }

    function getAllUserDepositIds(address _user) public view virtual returns (uint256[] memory) {
        return allUserDepositIds[_user].values();
    }

    /// @notice EMERGENCY ONLY
    function toggleUnlockAll() external virtual onlyOwner {
        unlockAll = unlockAll ? false : true;
    }

    function _withdraw(uint256 _depositId, uint256 _amount) public returns(bool) {
        DepositInfo storage depositCur = depositInfo[msg.sender][_depositId];
        if (depositCur.depositAmount == 0) {
            return false;
        }
        // Any deposit can be withdrawn if kill swith was used
        if (!unlockAll) {
            require(block.timestamp >= depositCur.lockedUntil, "Position is still locked");
        }
        uint256 depositAmount = depositCur.depositAmount;

        if (_amount > depositAmount) {
            _amount = depositAmount;
        }

        depositCur.depositAmount -= _amount;

        if (depositCur.depositAmount == 0) {
            require(allUserDepositIds[msg.sender].remove(_depositId), 'depositId does not exist');
        }

        // Interactions
        magic.safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _depositId, _amount);
        return true;
    }

    function _addDeposit(address _user) internal virtual returns (DepositInfo storage depositCur, uint256 newDepositId) {
        // start depositId from 1
        newDepositId = ++currentId[_user];
        allUserDepositIds[_user].add(newDepositId);
        depositCur = depositInfo[_user][newDepositId];
    }

    function _beforeTokenTransfer(address, address, uint256) internal pure override {
        revert("Non-transferable");
    }
}
