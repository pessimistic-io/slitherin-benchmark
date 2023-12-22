// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

/// @notice Provides a flexible and updatable auth pattern which is completely separate from application logic.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/security/AuthBase.sol)
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/auth/Auth.sol)
/// @dev Needs constructor or initializer
abstract contract AuthBase {
    error Auth__Unauthorized(address user, address target, bytes4 functionSig);

    event OwnerUpdated(address indexed user, address indexed newOwner);

    event AuthorityUpdated(address indexed user, Authority indexed newAuthority);

    address public owner;

    Authority public authority;

    // slither-disable-next-line naming-convention
    function setup(address _owner, Authority _authority) internal {
        owner = _owner;
        authority = _authority;

        emit OwnerUpdated(msg.sender, _owner);
        emit AuthorityUpdated(msg.sender, _authority);
    }

    modifier requiresAuth() virtual {
        if (!isAuthorized(msg.sender, msg.sig)) revert Auth__Unauthorized(msg.sender, address(this), msg.sig);

        _;
    }

    function isAuthorized(address user, bytes4 functionSig) internal view virtual returns (bool) {
        Authority auth = authority; // Memoizing authority saves us a warm SLOAD, around 100 gas.

        // Checking if the caller is the owner only after calling the authority saves gas in most cases, but be
        // aware that this makes protected functions uncallable even to the owner if the authority is out of order.
        return (address(auth) != address(0) && auth.canCall(user, address(this), functionSig)) || user == owner;
    }

    function setAuthority(Authority newAuthority) public virtual {
        // We check if the caller is the owner first because we want to ensure they can
        // always swap out the authority even if it's reverting or using up a lot of gas.
        require(msg.sender == owner || authority.canCall(msg.sender, address(this), msg.sig));

        authority = newAuthority;

        emit AuthorityUpdated(msg.sender, newAuthority);
    }

    function setOwner(address newOwner) public virtual requiresAuth {
        // slither-disable-next-line missing-zero-check
        owner = newOwner;

        emit OwnerUpdated(msg.sender, newOwner);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    // slither-disable-next-line naming-convention,unused-state
    uint256[48] private __gap;
}

/// @notice A generic interface for a contract which provides authorization data to an Auth instance.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/security/AuthBase.sol)
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/auth/Auth.sol)
interface Authority {
    function canCall(
        address user,
        address target,
        bytes4 functionSig
    ) external view returns (bool);
}

