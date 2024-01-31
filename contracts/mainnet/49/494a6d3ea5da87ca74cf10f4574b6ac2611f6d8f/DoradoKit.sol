// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./Clones.sol";
import "./SafeCast.sol";
import "./IDoradoLogic.sol";
import "./IDorado.sol";

string constant CANNOT_USE_ZERO = "Cannot use 0 address";
string constant COLLECTION_NOT_EXIST = "Collection not exist";
string constant FEE_RATE_ERROR = "FeeRate Exceeded";
string constant OWNER_ERROR = "Ownable: caller is not the owner";

uint256 constant _FEE_RATE_BITS = 16; // feeRate max value = 10000, bits = 0xFFFF = 65535.

contract DoradoKit is IDorado {
    event SignerChanged(address indexed newSignerAddress);
    event WithdrawChanged(address indexed newWithdrawAddress);
    event FeeRateChanged(address collection, uint256 oldFeeRate, uint256 newFeeRate);
    event CreateCollection(address _newClone, address _owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    address private _owner;
    address private _pendingOwner;

    address internal _signerAddress;
    address internal _withdrawAddress;

    address private _implementation;

    mapping(address => address[]) public allClones;
    mapping(address => uint256) private _collections;

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    constructor(address addressForSigner, address addressForWithdraw) {
        require(addressForSigner != address(0), CANNOT_USE_ZERO);
        require(addressForWithdraw != address(0), CANNOT_USE_ZERO);

        _signerAddress = addressForSigner;
        _withdrawAddress = addressForWithdraw;

        _owner = msg.sender;
    }

    function setImplementation(address implementation) external onlyOwner {
        require(implementation != address(0), CANNOT_USE_ZERO);
        _implementation = implementation;
    }

    function createCollection(
        string calldata name,
        string calldata symbol,
        uint64 maxTokens,
        bool burnable,
        uint96 feeNumerator,
        uint96 feeRate,
        address treasury,
        string[] calldata uris
    ) external {
        require(_implementation != address(0), CANNOT_USE_ZERO);
        require(feeRate <= 10000, FEE_RATE_ERROR);

        // impl by EIP-1167(https://eips.ethereum.org/EIPS/eip-1167).
        // use (https://github.com/optionality/clone-factory/blob/master/contracts/CloneFactory.sol)
        address identicalChild = Clones.clone(_implementation);
        allClones[msg.sender].push(identicalChild);

        _collections[identicalChild] = feeRate;

        IDoradoLogic(identicalChild).initialize(name, symbol, maxTokens, burnable, feeNumerator, treasury, uris);

        emit CreateCollection(identicalChild, msg.sender);
    }

    function returnClones(address _creator) external view returns (address[] memory) {
        return allClones[_creator];
    }

    // =============================================================
    //                        Wallet
    // =============================================================
    function viewSigner() public view returns (address) {
        return (_signerAddress);
    }

    function viewWithdraw() public view returns (address) {
        return (_withdrawAddress);
    }

    function changeSigner(address newAddress) external onlyOwner {
        require(newAddress != address(0), CANNOT_USE_ZERO);
        _signerAddress = newAddress;
        emit SignerChanged(newAddress);
    }

    function changeWithdraw(address newAddress) external onlyOwner {
        require(newAddress != address(0), CANNOT_USE_ZERO);
        _withdrawAddress = newAddress;
        emit WithdrawChanged(newAddress);
    }

    function setRateOverride(address collection, uint16 rate) external onlyOwner {
        require(rate <= 10000, FEE_RATE_ERROR);
        require(collection != address(0), COLLECTION_NOT_EXIST);
        uint256 value = _collections[collection] & 0xFFFF;
        // save at the lowest bits.
        emit FeeRateChanged(collection, value, rate);
        _collections[collection] = rate;
    }

    function getFeeRateOf(address collection) external view override returns (uint16) {
        return uint16(_collections[collection] & 0xFFFF);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() private view {
        require(owner() == msg.sender, OWNER_ERROR);
    }

    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    function acceptOwnership() external {
        address sender = msg.sender;
        require(pendingOwner() == sender, OWNER_ERROR);

        delete _pendingOwner;
        address oldOwner = owner();
        _owner = sender;
        emit OwnershipTransferred(oldOwner, sender);
    }
}

