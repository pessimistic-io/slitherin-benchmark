// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./Ownable.sol";
import "./IERC20.sol";
import "./EnumerableSet.sol";

import "./NitroPoolMinimal.sol";

import "./INFTPool.sol";
import "./INitroPoolFactory.sol";
import "./IProtocolToken.sol";
import "./IXToken.sol";

contract NitroPoolMinimalFactory is Ownable, INitroPoolFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    // (1%) max authorized default fee
    uint256 public constant MAX_DEFAULT_FEE = 100;

    IProtocolToken public immutable protocolToken;
    IXToken public immutable xToken;
    address private immutable _WETH;

    // To receive fees when defaultFee is set
    address public override feeAddress;

    // To recover rewards from emergency closed nitro pools
    address public override emergencyRecoveryAddress;

    // Default fee for nitro pools (*1e2)
    uint256 public defaultFee;

    // Owners or nitro addresses exempted from default fee
    EnumerableSet.AddressSet internal _exemptedAddresses;

    // All nitro pools
    EnumerableSet.AddressSet internal _nitroPools;

    // All published nitro pools
    EnumerableSet.AddressSet private _publishedNitroPools;

    // Published nitro pools per NFTPool
    mapping(address => EnumerableSet.AddressSet) private _nftPoolPublishedNitroPools;

    // Nitro pools per owner
    mapping(address => EnumerableSet.AddressSet) internal _ownerNitroPools;

    // ======================================================================== //
    // ============================== EVENTS ================================== //
    // ======================================================================== //

    event CreateNitroPool(address nitroAddress);
    event PublishNitroPool(address nitroAddress);
    event SetDefaultFee(uint256 fee);
    event SetFeeAddress(address feeAddress);
    event SetEmergencyRecoveryAddress(address emergencyRecoveryAddress);
    event SetExemptedAddress(address exemptedAddress, bool isExempted);
    event SetNitroPoolOwner(address previousOwner, address newOwner);

    // ======================================================================== //
    // ============================== ERRORS ================================== //
    // ======================================================================== //

    error UnknownNitroPool();
    error InvalidAmount();

    // ======================================================================= //
    // ============================= MODIFIERS =============================== //
    // ======================================================================= //

    modifier nitroPoolExists(address nitroPoolAddress) {
        if (!_nitroPools.contains(nitroPoolAddress)) revert UnknownNitroPool();
        _;
    }

    constructor(
        IProtocolToken _protocolToken,
        IXToken _xToken,
        address _weth,
        address _emergencyRecoveryAddress,
        address _feeAddress
    ) {
        address zeroAddr = address(0);
        if (_weth == zeroAddr || _emergencyRecoveryAddress == zeroAddr || _feeAddress == zeroAddr) revert ZeroAddress();

        protocolToken = _protocolToken;
        xToken = _xToken;
        _WETH = _weth;
        emergencyRecoveryAddress = _emergencyRecoveryAddress;
        feeAddress = _feeAddress;
    }

    // ======================================================================= //
    // =========================== EXTERNAL VIEW ============================= //
    // ======================================================================= //

    function WETH() public view override returns (address) {
        return _WETH;
    }

    /**
     * @dev Returns the number of nitroPools
     */
    function nitroPoolsLength() external view returns (uint256) {
        return _nitroPools.length();
    }

    /**
     * @dev Returns a nitroPool from its "index"
     */
    function getNitroPool(uint256 index) external view returns (address) {
        return _nitroPools.at(index);
    }

    /**
     * @dev Returns the number of published nitroPools
     */
    function publishedNitroPoolsLength() external view returns (uint256) {
        return _publishedNitroPools.length();
    }

    /**
     * @dev Returns a published nitroPool from its "index"
     */
    function getPublishedNitroPool(uint256 index) external view returns (address) {
        return _publishedNitroPools.at(index);
    }

    /**
     * @dev Returns the number of published nitroPools linked to "nftPoolAddress" NFTPool
     */
    function nftPoolPublishedNitroPoolsLength(address nftPoolAddress) external view returns (uint256) {
        return _nftPoolPublishedNitroPools[nftPoolAddress].length();
    }

    /**
     * @dev Returns a published nitroPool linked to "nftPoolAddress" from its "index"
     */
    function getNftPoolPublishedNitroPool(address nftPoolAddress, uint256 index) external view returns (address) {
        return _nftPoolPublishedNitroPools[nftPoolAddress].at(index);
    }

    /**
     * @dev Returns the number of nitroPools owned by "userAddress"
     */
    function ownerNitroPoolsLength(address userAddress) external view returns (uint256) {
        return _ownerNitroPools[userAddress].length();
    }

    /**
     * @dev Returns a nitroPool owned by "userAddress" from its "index"
     */
    function getOwnerNitroPool(address userAddress, uint256 index) external view returns (address) {
        return _ownerNitroPools[userAddress].at(index);
    }

    /**
     * @dev Returns the number of exemptedAddresses
     */
    function exemptedAddressesLength() external view returns (uint256) {
        return _exemptedAddresses.length();
    }

    /**
     * @dev Returns an exemptedAddress from its "index"
     */
    function getExemptedAddress(uint256 index) external view returns (address) {
        return _exemptedAddresses.at(index);
    }

    /**
     * @dev Returns if a given address is in exemptedAddresses
     */
    function isExemptedAddress(address checkedAddress) external view returns (bool) {
        return _exemptedAddresses.contains(checkedAddress);
    }

    /**
     * @dev Returns the fee for "nitroPoolAddress" address
     */
    function getNitroPoolFee(address nitroPoolAddress, address ownerAddress) external view override returns (uint256) {
        if (_exemptedAddresses.contains(nitroPoolAddress) || _exemptedAddresses.contains(ownerAddress)) {
            return 0;
        }
        return defaultFee;
    }

    // ======================================================================= //
    // ========================== STATE TRANSITIONS ========================== //
    // ======================================================================= //

    /**
     * @dev Deploys a new Nitro Pool
     */
    function createNitroPool(
        address nftPoolAddress,
        IERC20Metadata[] memory rewardTokens,
        uint256[] memory rewardStartTimes,
        uint256[] memory rewardsPerSecond,
        NitroPoolMinimal.PoolSettings memory _settings
    ) external virtual returns (address nitroPool) {
        // Initialize new nitro pool
        nitroPool = address(
            new NitroPoolMinimal(
                protocolToken,
                xToken,
                msg.sender,
                INFTPool(nftPoolAddress),
                rewardTokens,
                rewardStartTimes,
                rewardsPerSecond,
                _settings
            )
        );

        // Add new nitro
        _nitroPools.add(nitroPool);
        _ownerNitroPools[msg.sender].add(nitroPool);

        emit CreateNitroPool(nitroPool);
    }

    /**
     * @dev Publish a Nitro Pool
     *
     * Must only be called by the Nitro Pool contract
     */
    function publishNitroPool(address nftAddress) external override nitroPoolExists(msg.sender) {
        _publishedNitroPools.add(msg.sender);

        _nftPoolPublishedNitroPools[nftAddress].add(msg.sender);

        emit PublishNitroPool(msg.sender);
    }

    /**
     * @dev Transfers a Nitro Pool's ownership
     *
     * Must only be called by the NitroPool contract
     */
    function setNitroPoolOwner(address previousOwner, address newOwner) external override nitroPoolExists(msg.sender) {
        if (!_ownerNitroPools[previousOwner].remove(msg.sender)) revert InvalidOwner();

        _ownerNitroPools[newOwner].add(msg.sender);

        emit SetNitroPoolOwner(previousOwner, newOwner);
    }

    /**
     * @dev Set nitroPools default fee (when adding rewards)
     *
     * Must only be called by the owner
     */
    function setDefaultFee(uint256 newFee) external onlyOwner {
        if (newFee > MAX_DEFAULT_FEE) revert InvalidAmount();

        defaultFee = newFee;
        emit SetDefaultFee(newFee);
    }

    /**
     * @dev Set fee address
     *
     * Must only be called by the owner
     */
    function setFeeAddress(address feeAddress_) external onlyOwner {
        if (feeAddress_ == address(0)) revert ZeroAddress();
        feeAddress = feeAddress_;
        emit SetFeeAddress(feeAddress_);
    }

    /**
     * @dev Add or remove exemptedAddresses
     *
     * Must only be called by the owner
     */
    function setExemptedAddress(address exemptedAddress, bool isExempted) external onlyOwner {
        if (exemptedAddress == address(0)) revert ZeroAddress();

        if (isExempted) _exemptedAddresses.add(exemptedAddress);
        else _exemptedAddresses.remove(exemptedAddress);

        emit SetExemptedAddress(exemptedAddress, isExempted);
    }

    /**
     * @dev Set emergencyRecoveryAddress
     *
     * Must only be called by the owner
     */
    function setEmergencyRecoveryAddress(address emergencyRecoveryAddress_) external onlyOwner {
        if (emergencyRecoveryAddress_ == address(0)) revert ZeroAddress();

        emergencyRecoveryAddress = emergencyRecoveryAddress_;
        emit SetEmergencyRecoveryAddress(emergencyRecoveryAddress_);
    }

    // ======================================================================= //
    // ============================== INTERNAL =============================== //
    // ======================================================================= //
    /**
     * @dev Utility function to get the current block timestamp
     */
    function _currentBlockTimestamp() internal view virtual returns (uint256) {
        /* solhint-disable not-rely-on-time */
        return block.timestamp;
    }
}

