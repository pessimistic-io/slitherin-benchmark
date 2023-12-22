// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable2StepUpgradeable.sol";
import "./EnumerableMapUpgradeable.sol";
import "./VoucherCore.sol";
import "./IVNFTDescriptor.sol";

contract SurfVoucher is VoucherCore, Ownable2StepUpgradeable {
    using EnumerableMapUpgradeable for EnumerableMapUpgradeable.UintToAddressMap;

    // The IVNFTDescriptor
    IVNFTDescriptor public voucherDescriptor;

    // slot id -> slot admin mapping
    EnumerableMapUpgradeable.UintToAddressMap private slotAdminMap;


    /**
     * @dev emit when voucherDescriptor changed
     */
    event VoucherDescriptorChanged(
        address previousDescriptor,
        address currentDescriptor
    );

    /**
     * @dev emit when admin of slot changed
     */
    event SlotAdminChanged(
        uint256 slot,
        address previousAdmin,
        address currentAdmin
    );

    /**
     * @dev emit when admin of slot renouced
     */
    event SlotAdminRenouced(uint256 slot, address previousAdmin);

    /// @custom:oz-upgrades-unsafe-allow constructor
    // constructor() initializer {}

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC165Upgradeable, IERC165Upgradeable)
        returns (bool)
    {
        return ERC165Upgradeable.supportsInterface(interfaceId);
    }

    /**
     * initialize method, called by proxy
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 unitDecimals_,
        address initOwner
    ) external initializer {
        require(initOwner != address(0));

        // call super _initialize 
        VoucherCore._initialize(name_, symbol_, unitDecimals_);
        // initialize owner
        _transferOwnership(initOwner);
    }

    /**
     * returns admin of slot
     */
    function slotAdminOf(uint256 slot) external view returns (address) {
        return _getSlotAdmin(slot);
    }

    /**
     * @notice Returns the token Id metadata URI
     * Example: '{_tokenBaseURI}/{tokenId}'
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(_exists(tokenId));

        return voucherDescriptor.tokenURI(tokenId);
    }

    /**
     * @notice Returns the contract URI for contract metadata
     * See {setContractURI(string)}
     */
    function contractURI() external view override returns (string memory) {
        return voucherDescriptor.contractURI();
    }

    /**
     * @notice Returns the slot ID URI for metadata
     * Example: '{_slotBaseURI}/{slot}'
     */
    function slotURI(
        uint256 slot
    ) external view override returns (string memory) {
        require(_existsSlot(slot));

        return voucherDescriptor.slotURI(slot);
    }

    /// Administrative functions

    /**
     * update voucherDescriptor
     *
     */
    function setVoucherDescriptor(
        IVNFTDescriptor voucherDescriptor_
    ) external onlyOwner {
        require(address(voucherDescriptor_) != address(0));

        IVNFTDescriptor previousDescriptor = voucherDescriptor;
        voucherDescriptor = voucherDescriptor_;

        emit VoucherDescriptorChanged(address(previousDescriptor), address(voucherDescriptor));
    }

    /**
     * set or update admin of slot
     *
     * @dev only owner
     */
    function setSlotAdmin(uint256 slot, address slotAdmin_) external onlyOwner {
        require(slotAdmin_ != address(0));

        (bool exists, address previousAdmin) = slotAdminMap.tryGet(slot);
        require(!(exists && previousAdmin == address(0)));

        // update storage
        slotAdminMap.set(slot, slotAdmin_);

        emit SlotAdminChanged(slot, previousAdmin, slotAdmin_);
    }

    /**
     * renouce admin of slot
     *
     * @dev only owner
     */
    function renouceSlotAdmin(uint256 slot) external {
        address slotAdmin = _getSlotAdmin(slot);
        require(slotAdmin == _msgSender());

        // update storage
        slotAdminMap.set(slot, address(0));

        emit SlotAdminRenouced(slot, slotAdmin);
    }

    /// Change state functions

    /**
     * @dev Mint access restricted sender with minter role
     *
     */
    function mint(
        uint256 slot,
        address user,
        uint256 units
    ) external returns (uint256) {
        address slotAdmin = _getSlotAdmin(slot);
        require(slotAdmin == _msgSender());

        return _mint(user, slot, units);
    }

    /**
     * @dev Burn access restricted sender with burner role
     *
     */
    function burn(uint256 tokenId) external override {
        address slotAdmin = _getSlotAdmin(slotOf(tokenId));
        require(slotAdmin == _msgSender());
        require(_isApprovedOrOwner(_msgSender(), tokenId));

        _burnVoucher(tokenId);
    }

    /// Internal functions
    /**
     * returns admin of slot, revert if slot not exists
     */
    function _getSlotAdmin(uint256 slot) internal view returns (address) {
        (bool exists, address slotAdmin) = slotAdminMap.tryGet(slot);
        require(exists);

        return slotAdmin;
    }

    /**
     * check if slot exists
     */
    function _existsSlot(uint256 slot) internal view returns (bool) {
        return slotAdminMap.contains(slot);
    }
}

