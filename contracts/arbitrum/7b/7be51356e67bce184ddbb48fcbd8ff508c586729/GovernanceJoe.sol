// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

/** Imports **/

import "./IERC20.sol";
import "./IVeJoeStaking.sol";
import "./IStableJoeStaking.sol";
import "./Errors.sol";

/// @title Governance Joe Token
/// @author Trader Joe
/// @notice Token that sums user's JOE token owned and locked in sJOE and veJOE contracts for governance purposes
contract GovernanceJoe {
    /** Public variables **/

    IERC20 public immutable joeTokenAddress;
    IVeJoeStaking public immutable veJoeAddress;
    IStableJoeStaking public immutable sJoeAddress;

    /** Private variables **/

    string private constant _name = "GovernanceJoe";
    string private constant _symbol = "gJOE";

    /** Constructor **/

    /// @notice Set token and contract addresses
    /// @param _joeTokenAddress The address of JOE token
    /// @param _veJoeAddress The address of veJOE staking contract. Can be set to zero if veJOE is not deployed on the chain
    /// @param _sJoeAddress The address of sJOE staking contract
    constructor(address _joeTokenAddress, address _veJoeAddress, address _sJoeAddress) {
        if (_joeTokenAddress == address(0) || _sJoeAddress == address(0)) {
            revert GovernanceJoe__ZeroAddress();
        }

        joeTokenAddress = IERC20(_joeTokenAddress);
        veJoeAddress = IVeJoeStaking(_veJoeAddress);
        sJoeAddress = IStableJoeStaking(_sJoeAddress);
    }

    /** External View Functions **/

    /// @notice View function to retrieve sum of user's balances
    /// @param account User's address
    /// @return joeTotalBalance Sum of balances for JOE token and JOE staked in veJOE + sJOE contracts of the user
    function balanceOf(address account) public view returns (uint256 joeTotalBalance) {
        joeTotalBalance += _joeBalance(account);
        joeTotalBalance += _veJoeUnderlying(account);
        joeTotalBalance += _sJoeUnderlying(account);

        return joeTotalBalance;
    }

    /// @notice Returns the name of the token.
    function name() public pure returns (string memory) {
        return _name;
    }

    /// @notice Returns the symbol of the token, usually a shorter version of the name
    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    /** Internal Functions **/

    /// @notice View function to retrieve the JOE token balance of an account
    /// @param account User's address
    /// @return JOE token balance of the user
    function _joeBalance(address account) internal view returns (uint256) {
        return joeTokenAddress.balanceOf(account);
    }

    /// @notice View function to retrieve amount of JOE token staked in veJOE contract by an account
    /// @param account User's address
    /// @return JOE locked in veJOE contract by the user
    function _veJoeUnderlying(address account) internal view returns (uint256) {
        if (address(veJoeAddress) == address(0)) {
            return 0;
        }

        IVeJoeStaking.UserInfo memory userInfo = veJoeAddress.userInfos(account);
        return userInfo.balance;
    }

    /// @notice View function to retrieve amount of JOE token staked in sJOE contract by an account
    /// @param account User's address
    /// @return JOE locked in sJOE contract by the user
    function _sJoeUnderlying(address account) internal view returns (uint256) {
        (uint256 amount, ) = sJoeAddress.getUserInfo(account, IERC20(address(0)));
        return amount;
    }
}

