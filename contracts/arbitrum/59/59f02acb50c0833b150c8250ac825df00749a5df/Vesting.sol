// SPDX-License-Identifier: GNU GPLv3
pragma solidity ^0.8.0;

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//                                                                            //
//                              #@@@@@@@@@@@@&,                               //
//                      .@@@@@   .@@@@@@@@@@@@@@@@@@@*                        //
//                  %@@@,    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    //
//               @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                 //
//             @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@               //
//           *@@@#    .@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@             //
//          *@@@%    &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            //
//          @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//                                                                            //
//          (@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@,           //
//          (@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@,           //
//                                                                            //
//          @@@@@   @@@@@@@@@   @@@@@@@@@   @@@@@@@@@   @@@@@@@@@             //
//            &@@@@@@@    #@@@@@@@.   ,@@@@@@@,   .@@@@@@@/    @@@@           //
//                                                                            //
//          @@@@@      @@@%    *@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//          @@@@@      @@@@    %@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//          .@@@@      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            //
//            @@@@@  &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@             //
//                (&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&(                 //
//                                                                            //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

// Interfaces
import { IERC20 } from "./IERC20.sol";

// Contracts
import { AccessControl } from "./AccessControl.sol";

// Libraries
import { SafeMath } from "./SafeMath.sol";
import { SafeERC20 } from "./SafeERC20.sol";

// Marinate Interface
interface IMarinate {
    function claimRewards() external;
}

/**
 * @title mUMAMI Team Vesting Contract
 * @author EncryptedBunny
 * @dev Creates a vesting contract that vests its balance of any ERC20 token to the
 * beneficiary, gradually in a linear fashion until start + duration. By then all
 * of the balance will have vested.
 * Deploy one contract per person, per token
 */

contract Vesting is AccessControl {
    /************************************************
     *  LIBRARIES
     ***********************************************/
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /************************************************
     *  EVENTS
     ***********************************************/
    event TokensReleased(address token, uint256 amount);
    event RewardClaimed(address token, address staker, uint256 amount);

    /************************************************
     *  STORAGE
     ***********************************************/

    IERC20 public token;

    address public _beneficiary;
    address public _treasury;

    uint256 public _cliff;
    uint256 public _start;
    uint256 public _duration;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice an array of reward tokens to issue rewards in
    address[] public rewardTokens;

    mapping(address => uint256) private _released;
    mapping(address => bool) public isRewardToken;

    /************************************************
     *  CONSTRUCTOR
     ***********************************************/
    /**
     * @param beneficiary_ address of the beneficiary to whom vested tokens are transferred
     * @param treasury_ address of treasury for remaining tokens to be returned to if rescinded
     * @param _tokenAddress address of vested token
     * @param cliffDuration_ duration in seconds of the cliff in which tokens will begin to vest
     * @param duration_ duration in seconds of the period in which the tokens will vest
     */

    constructor(
        address beneficiary_,
        address treasury_,
        address _tokenAddress,
        uint256 cliffDuration_,
        uint256 duration_
    ) {
        require(beneficiary_ != address(0), "Beneficiary address cannot be 0");
        require(cliffDuration_ <= duration_, "Cliff should be <= duration");
        require(duration_ > 0, "Duration must be more than 0");
        require(_tokenAddress != address(0), "Token address cannot be 0");

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        _beneficiary = beneficiary_;
        _treasury = treasury_;
        _duration = duration_;
        _cliff = block.timestamp + cliffDuration_;
        _start = block.timestamp;

        token = IERC20(_tokenAddress);
    }

    /************************************************
     *  VESTING FUNCTIONS
     ***********************************************/
    /**
     * @dev Rescind the vesting contract. If the owner of this contract wants to stop vesting they can do it with this function.
     * When called rescind sends the amount of tokens already vested to the beneficiary and sends the rest back to nominated treasury.
     * It also updates the _duration variable to reflect that vesting for this contract has ended.
     */
    function rescind() public onlyAdmin {
        uint256 releasableNow = releasable();
        uint256 toRescind = token.balanceOf(address(this)) - releasableNow;
        token.safeTransfer(_treasury, toRescind);
        _duration = block.timestamp - _start; //now _start + duration == block.timestamp
        token.safeTransfer(_beneficiary, releasableNow);
    }

    /**
     * @return the amount of the token released.
     */
    function released() public view returns (uint256) {
        return _released[address(token)];
    }

    /**
     * @return the amount of token that can be released at the current block timestamp.
     */
    function releasable() public view returns (uint256) {
        return _releasableAmount();
    }

    /**
     * @notice Transfers vested tokens to beneficiary. Also run claim on Marinate
     */
    function release() public {
        // Marinate Claim
        claimMarinateRewards();

        // Vested token claim
        uint256 unreleased = _releasableAmount();

        require(unreleased > 0);
        address tokenAddress = address(token);
        _released[tokenAddress] = _released[tokenAddress] + unreleased;

        token.safeTransfer(_beneficiary, unreleased);

        emit TokensReleased(tokenAddress, unreleased);
    }

    /**
     * @dev Calculates the amount that has already vested but hasn't been released yet.
     */
    function _releasableAmount() private view returns (uint256) {
        return _vestedAmount() - _released[address(token)];
    }

    /**
     * @dev Calculates the amount that has already vested.
     */
    function _vestedAmount() private view returns (uint256) {
        uint256 currentBalance = token.balanceOf(address(this));
        uint256 totalBalance = currentBalance + _released[address(token)];

        if (block.timestamp < _cliff) {
            return 0;
        } else if (block.timestamp >= _start + _duration) {
            return totalBalance;
        } else {
            return (totalBalance * (block.timestamp - _start)) / _duration;
        }
    }

    /************************************************
     *  REWARD CLAIMING FUNCTIONS
     ***********************************************/
    /**
     * @dev Claim rewards from Marinate.
     */
    function claimMarinateRewards() public {
        uint256 currentBalance = token.balanceOf(address(this));

        IMarinate(address(token)).claimRewards();

        uint256 claimedAmount = token.balanceOf(address(this)) - currentBalance;
        token.safeTransfer(_beneficiary, claimedAmount);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            IERC20 reward = IERC20(rewardTokens[i]);
            uint256 toTransfer = reward.balanceOf(address(this));
            reward.safeTransfer(_beneficiary, toTransfer);
            emit RewardClaimed(rewardTokens[i], _beneficiary, toTransfer);
        }
    }

    /**
     * @dev Add reward token to withdraw.
     */
    function addRewardToken(address rewardToken) external onlyAdmin {
        require(address(token) != rewardToken, "Can't be Vested Token");
        require(!isRewardToken[rewardToken], "Reward token exists");
        isRewardToken[rewardToken] = true;
        rewardTokens.push(rewardToken);
    }

    /**
     * @dev Remove reward token to withdraw.
     */
    function removeRewardToken(address rewardToken) external onlyAdmin {
        require(address(token) != rewardToken, "Can't be Vested Token");
        require(isRewardToken[rewardToken], "Reward token does not exist");
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] == rewardToken) {
                rewardTokens[i] = rewardTokens[rewardTokens.length - 1];
                rewardTokens.pop();
                isRewardToken[rewardToken] = false;
            }
        }
    }

    /************************************************
     *  ADMIN
     ***********************************************/

    /**
     * @notice recover eth
     */
    function recoverEth() external onlyAdmin {
        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Withdraw failed");
    }

    /**
     * @dev Access control.
     */
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }
}

