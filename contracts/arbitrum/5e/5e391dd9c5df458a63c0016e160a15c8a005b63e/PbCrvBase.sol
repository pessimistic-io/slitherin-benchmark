// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./IERC20Upgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

import "./IPool.sol";
import "./IGauge.sol";
import "./ILendingPool.sol";

abstract contract PbCrvBase is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {

    IERC20Upgradeable public CRV;
    IERC20Upgradeable public lpToken;
    IERC20Upgradeable public rewardToken;
    IPool public pool;
    IGauge public gauge;
    address public treasury;
    uint public yieldFeePerc;

    uint public accRewardPerlpToken;
    ILendingPool public lendingPool;
    IERC20Upgradeable public aToken;
    uint public lastATokenAmt;

    struct User {
        uint lpTokenBalance;
        uint rewardStartAt;
    }
    mapping(address => User) public userInfo;
    mapping(address => uint) internal depositedBlock;

    event Deposit(address indexed account, address indexed tokenDeposit, uint amountToken, uint amountlpToken);
    event Withdraw(address indexed account, address indexed tokenWithdraw, uint amountlpToken, uint amountToken);
    event Harvest(uint harvestedfarmTokenAmt, uint swappedRewardTokenAfterFee, uint fee);
    event Claim(address indexed account, uint rewardTokenAmt);
    event SetTreasury(address oldTreasury, address newTreasury);
    event SetYieldFeePerc(uint oldYieldFeePerc, uint newYieldFeePerc);

    function deposit(IERC20Upgradeable token, uint amount, uint amountOutMin) external payable virtual;

    function withdraw(IERC20Upgradeable token, uint lpTokenAmt, uint amountOutMin) external payable virtual;

    function harvest() public virtual;

    function claim() public virtual;

    function setTreasury(address _treasury) external onlyOwner {
        emit SetTreasury(treasury, _treasury);
        treasury = _treasury;
    }

    function setYieldFeePerc(uint _yieldFeePerc) external onlyOwner {
        require(_yieldFeePerc <= 1000, "Fee cannot over 10%");
        emit SetYieldFeePerc(yieldFeePerc, _yieldFeePerc);
        yieldFeePerc = _yieldFeePerc;
    }

    function pauseContract() external onlyOwner {
        _pause();
    }

    function unPauseContract() external onlyOwner {
        _unpause();
    }

    function getPricePerFullShareInUSD() public view virtual returns (uint);

    function getAllPool() public view virtual returns (uint);

    function getAllPoolInUSD() external view virtual returns (uint);

    function getPoolPendingReward() external virtual returns (uint);

    function getUserPendingReward(address account) external view virtual returns (uint);

    function getUserBalance(address account) external view virtual returns (uint);

    function getUserBalanceInUSD(address account) external view virtual returns (uint);

    function _authorizeUpgrade(address) internal override onlyOwner {}

    uint[38] private __gap;
}

