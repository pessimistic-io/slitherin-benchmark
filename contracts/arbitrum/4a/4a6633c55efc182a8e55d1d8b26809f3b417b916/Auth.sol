// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0 <0.9.0;

/**
 * @dev Multiple authority management system.
 * There are no roles, other than owner and authorised.
 * Both can do everything, but owner can add and remove authorised addresses.
 */
abstract contract Auth {

    address internal _owner;
    mapping (address => bool) internal _authorizations;

    event OwnershipTransferred(address owner);

    constructor(address owner) {
        _owner = owner;
        _authorizations[_owner] = true;
    }

    /**
     * @dev Function modifier to require caller to be contract owner
     */
    modifier onlyOwner() {
        require(isOwner(msg.sender), "!OWNER"); _;
    }

    /**
     * @dev Function modifier to require caller to be authorized
     */
    modifier authorized() {
        require(isAuthorized(msg.sender), "!AUTHORIZED"); _;
    }

    /**
     * @dev Authorize address. Owner only.
     */
    function authorize(address adr) public onlyOwner {
        _authorizations[adr] = true;
    }

    /**
     * @dev Remove address' authorization. Owner only.
     */
    function unauthorize(address adr) public onlyOwner {
        _authorizations[adr] = false;
    }

    /**
     * @dev Check if address is _owner.
     */
    function isOwner(address account) public view returns (bool) {
        return account == _owner;
    }

    /**
     * @dev Return address' authorization status
     */
    function isAuthorized(address adr) public view returns (bool) {
        return _authorizations[adr];
    }

    /**
     * @dev Transfer ownership to a new address. Caller must be _owner. Leaves old _owner authorized.
     */
    function transferOwnership(address payable adr) public onlyOwner {
        _owner = adr;
        _authorizations[adr] = true;
        emit OwnershipTransferred(adr);
    }
}

