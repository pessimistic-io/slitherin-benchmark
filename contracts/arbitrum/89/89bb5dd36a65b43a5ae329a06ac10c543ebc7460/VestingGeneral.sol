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

/**
 * @title Generic ERC20 Token Team Vesting Contract
 * @author EncryptedBunny
 * @dev Creates a vesting contract that vests its balance of any ERC20 token to the
 * beneficiary, gradually in a linear fashion until start + duration. By then all
 * of the balance will have vested.
 * Deploy one contract per person, per token
 */

contract VestingGeneral is AccessControl {
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

    mapping(address => uint256) private _released;

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
     * @notice Transfers vested tokens to beneficiary.
     */
    function release() public {
       
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

