// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./AddressUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IOperators.sol";

contract SwapAndAirdrop is Initializable, ReentrancyGuardUpgradeable {
    uint256 internal constant BASIS_POINTS_DIVISOR = 100000;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    enum PILL_TYPE {
        NONE, BLUE_PILL, RED_PILL
    }

    struct AirdropInfo {
        address account;
        uint256 amount;
    }

    struct RatioInfo {
        address account;
        uint256 ratio;
    }

    struct PillInfo {
        address account;
        PILL_TYPE pillType;
    }

    IOperators public operators;

    address private vela;
    address private oldEsVela;
    address private newEsVela;
    address private feeManager;

    uint256 public bluePillStartTime;
    uint256 public bluePillPeriod;
    uint256 public redPillStartTime;
    uint256 public startRatio;
    bool public isRedPillEnabled;

    // variables
   
    mapping(address => uint256) public claimableAmount;
    mapping(address => uint256) public ratio;
    mapping(address => PILL_TYPE) public pill;

    event Swap(address indexed account, uint256 amount);
    event Claim(address indexed account, bool isBluePill, bool isVela, uint256 amount);

    modifier onlyOperator(uint256 level) {
        require(operators.getOperatorLevel(msg.sender) >= level, "invalid operator");
        _;
    }

    /* ========== INITIALIZE FUNCTIONS ========== */

    function initialize(address _operators, address _vela, address _oldEsVela, address _newEsVela) public initializer {
        require(AddressUpgradeable.isContract(_operators), "operators invalid");

        __ReentrancyGuard_init();
        operators = IOperators(_operators);
        vela = _vela;
        oldEsVela = _oldEsVela;
        newEsVela = _newEsVela;
        startRatio = 80000; // 0.8
        bluePillPeriod = 6 days;
    }

    function setFeeManager(address _feeManager) external onlyOperator(3) {
        feeManager = _feeManager;
    }

    function updatePillInfo(uint256 _bluePillStartTime, uint256 _bluePillPeriod, uint256 _redPillStartTime, uint256 _startRatio) external onlyOperator(3) {
        bluePillStartTime = _bluePillStartTime;
        bluePillPeriod = _bluePillPeriod;
        redPillStartTime = _redPillStartTime;
        startRatio = _startRatio;
    }

    function setIsRedPillEnabled(bool _isRedPillEnabled) external onlyOperator(3) {
        isRedPillEnabled = _isRedPillEnabled;
    }
    /* ========== CORE FUNCTIONS ========== */

    // deposit stablecoin to mint vusd
    function _swap(address _account, uint256 _amount) internal {
        require(_amount > 0, "zero amount");
        IERC20Upgradeable(oldEsVela).safeTransferFrom(_account, feeManager, _amount);
        IERC20Upgradeable(newEsVela).safeTransfer(_account, _amount);
        emit Swap(_account, _amount);
    }

    function swap(uint256 _amount) external nonReentrant {
        _swap(msg.sender, _amount);
    }

    function swapAll() external nonReentrant {
        _swap(msg.sender, IERC20Upgradeable(oldEsVela).balanceOf(msg.sender));
    }

    function selectPill(PILL_TYPE pillType) external nonReentrant {
        require(claimableAmount[msg.sender] > 0, "not allowed to airdrop");
        require(pill[msg.sender] == PILL_TYPE.NONE, 'You already selected Pill');
        pill[msg.sender] = pillType;
    }

    function claim(PILL_TYPE pillType, bool isVela) external nonReentrant {
        require(claimableAmount[msg.sender] > 0, "zero amount");
        if (pillType == PILL_TYPE.BLUE_PILL) {
            require(pill[msg.sender] != PILL_TYPE.RED_PILL, "you are not in right pill");
            require(block.timestamp > bluePillStartTime && block.timestamp < bluePillStartTime + bluePillPeriod, 'not in blue pill');
            if (isVela) {
                uint256 amount = claimableAmount[msg.sender];
                claimableAmount[msg.sender] = 0;
                IERC20Upgradeable(vela).safeTransfer(msg.sender, amount);
                emit Claim(msg.sender, true, isVela, amount);
            } else {
                uint256 amount = 2 * claimableAmount[msg.sender];
                claimableAmount[msg.sender] = 0;
                IERC20Upgradeable(newEsVela).safeTransfer(msg.sender, amount);
                emit Claim(msg.sender, true, isVela, amount);
            }
        } else {
            require(block.timestamp > redPillStartTime && isRedPillEnabled, 'not in red pill');
            if (isVela) {
                uint256 amount = (startRatio + ratio[msg.sender]) * claimableAmount[msg.sender] / BASIS_POINTS_DIVISOR;
                claimableAmount[msg.sender] = 0;
                IERC20Upgradeable(vela).safeTransfer(msg.sender, amount);
                emit Claim(msg.sender, false, isVela, amount);
            } else {
                uint256 amount = 2 * (startRatio + ratio[msg.sender]) * claimableAmount[msg.sender] / BASIS_POINTS_DIVISOR;
                claimableAmount[msg.sender] = 0;
                IERC20Upgradeable(newEsVela).safeTransfer(msg.sender, amount);
                emit Claim(msg.sender, false, isVela, amount);
            }
        }
    }

    function distributeAirdrops(AirdropInfo[] calldata _airdrops) external onlyOperator(3) {
        uint256 length = _airdrops.length;
        for (uint256 i; i < length; ) {
            claimableAmount[_airdrops[i].account] = _airdrops[i].amount;

            unchecked {
                ++i;
            }
        }
    }

    function updateUserPillRatios(RatioInfo[] calldata _ratios) external onlyOperator(3) {
        uint256 length = _ratios.length;
        for (uint256 i; i < length; ) {
            ratio[_ratios[i].account] = _ratios[i].ratio;

            unchecked {
                ++i;
            }
        }
        isRedPillEnabled = true;
    }

    function updateUserPill(PillInfo[] calldata _pill) external onlyOperator(3) {
        uint256 length = _pill.length;
        for (uint256 i; i < length; ) {
            pill[_pill[i].account] = _pill[i].pillType;

            unchecked {
                ++i;
            }
        }
    }

    function rescueToken(address _token, uint256 _amount) external onlyOperator(4) {
        IERC20Upgradeable(_token).safeTransfer(msg.sender, _amount);
    }

    function getPllInfo() external view returns (uint256, uint256, uint256, uint256, bool){
        return (bluePillStartTime, bluePillPeriod, redPillStartTime, startRatio, isRedPillEnabled);
    }

    function getUserPill(address _user) external view returns (uint256, uint256, PILL_TYPE) {
        return (claimableAmount[_user], ratio[_user], pill[_user]);
    }
}
