//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {IERC20} from "./IERC20.sol";
import {IStakingRewards} from "./IStakingRewards.sol";

// Contracts
import {Initializable} from "./utils_Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ISSOV} from "./ISSOV.sol";

// Libraries
import {BokkyPooBahsDateTimeLibrary} from "./BokkyPooBahsDateTimeLibrary.sol";
import {SafeERC20} from "./SafeERC20.sol";

contract SSOVDelegator is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    /// @dev exerciseFee % denominator
    uint256 public constant denominator = 1e10;

    /// @dev fee incentive for exercising CALL Options in SSOV
    uint256 public exerciseFee;

    /// @dev fee cap for exercising
    uint256 public exerciseFeeCap;

    /// @dev SSOV
    ISSOV public ssov;

    /// @dev SSOV Token
    IERC20 public ssovToken;

    /// @dev epoch => strike => total balance
    mapping(uint256 => mapping(uint256 => uint256)) public totalBalances;

    /// @dev epoch => (strike => total pnl)
    mapping(uint256 => mapping(uint256 => uint256)) public totalPnl;

    /// @dev abi.encodePacked(user, strike) => epoch => user balance
    mapping(bytes32 => mapping(uint256 => uint256)) public balances;

    event Delegate(
        address indexed user,
        address indexed sender,
        uint256 indexed epoch,
        uint256 strike,
        uint256 amount
    );

    event SetExerciseFee(address sender, uint256 exerciseFee);

    event SetExerciseFeeCap(address sender, uint256 exerciseFeeCap);

    event Exercise(
        address indexed user,
        uint256 epoch,
        uint256 strike,
        uint256 pnl,
        uint256 exerciseFee
    );

    event Withdrawal(
        address indexed user,
        uint256 epoch,
        uint256 strike,
        uint256 amount
    );

    event Claim(
        address indexed user,
        uint256 epoch,
        address sender,
        uint256 amount
    );

    /// @dev Initialize
    /// @param _ssov address of SSOV
    /// @param _ssovToken address of the token of the SSOV
    /// @param _exerciseFee exercise fee for the user calling exercise address of Asset Swapper contract
    /// @param _exerciseFeeCap max fee the user calling exercise can receive
    function initialize(
        address _ssov,
        address _ssovToken,
        uint256 _exerciseFee,
        uint256 _exerciseFeeCap
    ) external {
        // initializer modifier is called in __Ownable_init
        require(
            address(_ssov) != address(0),
            'Delegator: Invalid SSOV address'
        );
        require(
            address(_ssovToken) != address(0),
            'Delegator: Invalid SSOV Token address'
        );
        require(_exerciseFee < denominator, 'Delegator: Invalid exercise fee');
        ssov = ISSOV(_ssov);
        ssovToken = IERC20(_ssovToken);
        exerciseFee = _exerciseFee;
        exerciseFeeCap = _exerciseFeeCap;

        __Ownable_init();

        emit SetExerciseFee(msg.sender, exerciseFee);
        emit SetExerciseFeeCap(msg.sender, _exerciseFeeCap);
    }

    /// @notice Set Exercise fee
    /// @dev Owner sets the exercise fee
    /// @param _exerciseFee exercise fee % for option exercise
    function setExerciseFee(uint256 _exerciseFee) external onlyOwner {
        require(_exerciseFee < denominator, 'Delegator: Invalid exercise fee');
        exerciseFee = _exerciseFee;
        emit SetExerciseFee(msg.sender, exerciseFee);
    }

    /// @notice Set Exercise fee cap
    /// @dev Owner sets the exercise fee cap
    /// @param _exerciseFeeCap exercise fee cap for option exercise
    function setExerciseFeeCap(uint256 _exerciseFeeCap) external onlyOwner {
        exerciseFeeCap = _exerciseFeeCap;
        emit SetExerciseFeeCap(msg.sender, _exerciseFeeCap);
    }

    /// @notice Delegate on behalf of user
    /// @dev Transfer doTokens for auto-exercise of ssov calls
    /// @param _epoch current ssov epoch
    /// @param _strike strike of the option to auto-exercise
    /// @param _amount amount of doTokens to transfer to delegator
    function delegate(
        uint256 _epoch,
        uint256 _strike,
        uint256 _amount,
        address _user
    ) external returns (bool) {
        require(_user != address(0), 'Delegator: User cannot be zero');
        bytes32 userStrike = keccak256(abi.encodePacked(_user, _strike));
        require(
            totalBalances[_epoch][_strike] == 0,
            'Delegator: Cannot deposit after exercise'
        );
        balances[userStrike][_epoch] += _amount;
        IERC20(ssov.epochStrikeTokens(_epoch, _strike)).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        emit Delegate(_user, msg.sender, _epoch, _strike, _amount);
        return true;
    }

    /// @notice Exercise an option on behalf of the user for a given epoch and strike
    /// @dev this function is not complete
    /// @param _epoch current ssov epoch
    /// @param _strike strike of the option to exercise
    /// @param _strikeIndex strike index of strikes[] array
    function exercise(
        uint256 _epoch,
        uint256 _strike,
        uint256 _strikeIndex
    ) external returns (uint256) {
        require(
            totalBalances[_epoch][_strike] == 0,
            'Delegator: Cannot exercise more than once'
        );
        IERC20 epochStrikeToken = IERC20(
            ssov.epochStrikeTokens(_epoch, _strike)
        );
        uint256 amount = epochStrikeToken.balanceOf(address(this));
        require(amount > 0, 'Delegator: Balance cannot be 0');
        totalBalances[_epoch][_strike] = amount;
        epochStrikeToken.safeApprove(address(ssov), amount);
        uint256 pnl = ssovToken.balanceOf(address(this));
        ssov.exercise(_strikeIndex, amount, address(this));
        pnl = ssovToken.balanceOf(address(this)) - pnl;
        uint256 fee = (pnl * exerciseFee) / denominator;
        // Ensure fee does not exceed cap
        if (fee > exerciseFeeCap) fee = exerciseFeeCap;
        pnl = pnl - fee;
        totalPnl[_epoch][_strike] = pnl;
        ssovToken.safeTransfer(msg.sender, fee);
        emit Exercise(msg.sender, _epoch, _strike, pnl, fee);
        return pnl;
    }

    /// @notice Withdraw doTokens from the ssov before monthly expiry
    /// @dev Cannot withdraw from the ssov if user balance = 0
    /// or balance<deposited amount
    /// @param _epoch epoch to withdraw doTokens from
    /// @param _strike strike price
    /// @param _amount amount of doTokens to withdraw
    function withdraw(
        uint256 _epoch,
        uint256 _strike,
        uint256 _amount
    ) external returns (uint256) {
        require(
            totalBalances[_epoch][_strike] == 0,
            'Delegator: Cannot withdraw after exercise'
        );
        bytes32 userStrike = keccak256(abi.encodePacked(msg.sender, _strike));
        balances[userStrike][_epoch] = balances[userStrike][_epoch] - _amount;
        IERC20(ssov.epochStrikeTokens(_epoch, _strike)).safeTransfer(
            msg.sender,
            _amount
        );
        emit Withdrawal(msg.sender, _epoch, _strike, _amount);
        return _amount;
    }

    /// @notice get pnl to claim from user's doToken deposit
    /// @param _epoch epoch to claim pnl from
    /// @param _strike strike price
    /// @param _user user claiming pnl
    function claimableAmount(
        uint256 _epoch,
        uint256 _strike,
        address _user
    ) public view returns (uint256) {
        bytes32 userStrike = keccak256(abi.encodePacked(_user, _strike));
        uint256 totalBalance = totalBalances[_epoch][_strike];
        if (totalBalance == 0) {
            return 0;
        } else {
            return
                (balances[userStrike][_epoch] * totalPnl[_epoch][_strike]) /
                totalBalance;
        }
    }

    /// @notice claim pnl for user
    /// @param _epoch epoch to claim pnl from
    /// @param _strike strike price
    /// @param _user user claiming pnl
    function claim(
        uint256 _epoch,
        uint256 _strike,
        address _user
    ) external returns (uint256) {
        uint256 claimAmount = claimableAmount(_epoch, _strike, _user);
        bytes32 userStrike = keccak256(abi.encodePacked(_user, _strike));
        require(claimAmount > 0, 'Delegator: Already claimed');
        balances[userStrike][_epoch] = 0;
        ssovToken.safeTransfer(_user, claimAmount);
        emit Claim(_user, _epoch, msg.sender, claimAmount);
        return claimAmount;
    }
}

