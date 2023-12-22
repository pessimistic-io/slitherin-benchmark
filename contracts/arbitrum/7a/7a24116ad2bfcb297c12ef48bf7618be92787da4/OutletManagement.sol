// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable2StepUpgradeable.sol";
import "./IERC165Upgradeable.sol";
import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./IERC721ReceiverUpgradeable.sol";
import "./Errors.sol";
import "./ISurfVoucher.sol";
import "./IOutletDescriptor.sol";
import "./IOutletManagement.sol";

contract OutletManagement is
    IOutletManagement,
    Initializable,
    IERC165Upgradeable,
    IVNFTReceiver,
    IERC721ReceiverUpgradeable,
    Ownable2StepUpgradeable
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    /// constants

    /// variables

    // slot id using in SurfVoucher
    uint256 public slotId;

    // The SurfVoucher
    ISurfVoucher public surfVoucher;

    // The IOutletDescriptor
    IOutletDescriptor public outletDescriptor;

    // outlet id set
    EnumerableSetUpgradeable.UintSet private outletIdSet;

    // outlet id -> OutletData mapping
    mapping(uint256 => OutletData) private outletDataMapping;

    // address -> token set in standby state 
    mapping(address => EnumerableSetUpgradeable.UintSet) private standbyTokenSetMapping;

    // id of outlet, start from 1
    uint32 private nextOutletId;

    /// events

    // emits when add new outlet
    event AddedOutlet(
        uint256 outletId,
        string name,
        address manager,
        bool isActive,
        uint256 creditQuota
    );

    // emits when outlet is removed
    event RemovedOutlet(uint256 outletId);

    // emits when deactivate outlet
    event DeactivatedOutlet(uint256 outletId);

    // emits when activate outlet
    event ActivatedOutlet(uint256 outletId);

    // emits when credit quota of outlet changed
    event OutletCreditQuotaChanged(
        uint256 outletId,
        uint256 previousQuota,
        uint256 currentQuota
    );

    // emits when manager of outlet changed
    event OutletManagerChanged(
        uint256 outletId,
        address previousManager,
        address currentManager
    );

    // emits when manager of outlet changed
    event OutletNameChanged(uint256 outletId, string previousName, string currentName);

    // emits when outlet descriptor changed
    event OutletDescriptorChanged(
        IOutletDescriptor previousDescriptor,
        IOutletDescriptor currentDescriptor
    );

    // emits when outlet issues new units
    event OutletIssuance(uint256 outletId, address receiver, uint256 units);

    // emits when outlet releases units
    event OutletReleasement(uint256 outletId, uint256 units);

    // emits when token entered standby status
    event StandbyEntrance(address from, uint256 tokenId);

    // emits when token cancelled standby status
    event StandbyCancelled(address from, uint256 tokenId);

    function initialize(
        ISurfVoucher surfVoucher_,
        IOutletDescriptor outletDescriptor_,
        uint256 slotId_,
        address initOwner
    ) external initializer {
        require(
            address(surfVoucher_) != address(0),
            Errors.INVALID_INPUT
        );
        require(initOwner != address(0), Errors.INVALID_INPUT);

        surfVoucher = surfVoucher_;
        _setOutletDescriptor(outletDescriptor_);
        slotId = slotId_;
        // initialize owner
        _transferOwnership(initOwner);

        nextOutletId = 1;
    }

    // ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) external pure override returns (bool) {
        return interfaceId == type(IERC721ReceiverUpgradeable).interfaceId 
            || interfaceId == type(IVNFTReceiver).interfaceId;
    }

    // implements IVNFTReceiver
    // reject
    function onVNFTReceived(
        address operator,
        address from,
        uint256 tokenId,
        uint256 units,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return bytes4(0);
    }

    // implements IERC721ReceiverUpgradeable 
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        uint256 slotId_ = surfVoucher.slotOf(tokenId);
        // only token of slotId 
        if (slotId_ != slotId) {
            return bytes4(0);
        }

        EnumerableSetUpgradeable.UintSet storage tokenSet = standbyTokenSetMapping[from];
        if (tokenSet.add(tokenId)) {
            emit StandbyEntrance(from, tokenId);
        }

        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }

    // returns next outlet id
    function _generateOutletId() internal returns (uint256) {
        return nextOutletId++;
    }

    /// View functions

    /**
     * returns all outlet id set
     */
    function allOutletIds() external view override returns (uint256[] memory) {
        return outletIdSet.values();
    }

    /**
     * returns outlet id set with given manager
     */
    function outletIdsOf(address manager) external view override returns (uint256[] memory) {
        uint256[] memory outletIdSet_ = outletIdSet.values();

        uint count = 0;
        for (uint i = 0; i < outletIdSet_.length; i++) {
            OutletData memory outletData = outletDataMapping[outletIdSet_[i]];
            if (outletData.manager == manager) {
                count++;
            }
        }

        if (count == 0) {
            return new uint256[] (0);
        }

        uint256[] memory result = new uint256[] (count);
        count = 0;
        for (uint i = 0; i < outletIdSet_.length; i++) {
            OutletData memory outletData = outletDataMapping[outletIdSet_[i]];
            if (outletData.manager == manager) {
                result[count] = outletIdSet_[i];
                count++;
            }
        }

        return result;
    }

    /**
     * returns outlet data by given id
     */
    function getOutletData( uint256 outletId) external view override returns (OutletData memory) {
        require(_exists(outletId), Errors.NONEXISTENCE);

        return outletDataMapping[outletId];
    }

    /**
     * returns standby token id set of given account
     */
    function getStandbyTokenIds(address account) external view returns (uint256[] memory) {
        return standbyTokenSetMapping[account].values();
    }

    /**
     * returns outlet metadata
     */
    function outletURI(uint256 outletId) external view override returns (string memory) {
        require(_exists(outletId), Errors.NONEXISTENCE);

        return outletDescriptor.outletURI(this, outletId);
    }

    /// Change state functions

    /**
     * issue new units
     * @dev only manager of outlet
     */
    function issue(uint256 outletId, address receiver, uint256 units) external returns (uint256 tokenId) {
        require(_exists(outletId), Errors.NONEXISTENCE);
        require(receiver != address(0), Errors.INVALID_INPUT);

        OutletData storage outletData = outletDataMapping[outletId];
        require(outletData.manager == _msgSender(), Errors.NON_AUTH);
        require(outletData.isActive, Errors.ILLEGAL_STATE);

        uint256 aviaiableQuota = _calcAviaiableQuota(outletData);
        require(units <= aviaiableQuota, Errors.EXCEEDS);

        // mint new token
        tokenId = surfVoucher.mint(slotId, receiver, units);

        // accumulate circulation
        outletData.circulation = outletData.circulation + units;

        emit OutletIssuance(outletId, receiver, units);
    }

    /**
     * release token
     */
    function release(uint256 tokenId, uint256 outletId) external {
        require(_exists(outletId), Errors.NONEXISTENCE);

        EnumerableSetUpgradeable.UintSet storage tokenSet = standbyTokenSetMapping[_msgSender()];
        require(tokenSet.contains(tokenId), Errors.ILLEGAL_STATE);

        // update storage
        OutletData storage outletData = outletDataMapping[outletId];
        require(outletData.isActive, Errors.ILLEGAL_STATE);

        // get units in token
        uint256 unitsInToken = surfVoucher.unitsInToken(tokenId);
        require(outletData.circulation >= unitsInToken, Errors.EXCEEDS);

        // burn token
        surfVoucher.burn(tokenId);

        // deduct circulation
        outletData.circulation = outletData.circulation - unitsInToken;

        // remove from standby
        tokenSet.remove(tokenId);

        emit OutletReleasement(outletId, unitsInToken);
    }

    /**
     * release token by owner
     * 
     * @dev only owner
     */
    function delegateRelease(uint256 tokenId, uint256 outletId) external onlyOwner {
        uint256 slotId_ = surfVoucher.slotOf(tokenId);
        require(slotId_ == slotId, Errors.ILLEGAL_STATE);

        require(_exists(outletId), Errors.NONEXISTENCE);

        // update storage
        OutletData storage outletData = outletDataMapping[outletId];

        // get units in token
        uint256 unitsInToken = surfVoucher.unitsInToken(tokenId);
        require(outletData.circulation >= unitsInToken, Errors.EXCEEDS);

        // burn token
        surfVoucher.burn(tokenId);

        // deduct circulation
        outletData.circulation = outletData.circulation - unitsInToken;

        emit OutletReleasement(outletId, unitsInToken);
    }

    /**
     * Cancel standby status
     */
    function cancelStandby(uint256 tokenId) external {
        EnumerableSetUpgradeable.UintSet storage tokenSet = standbyTokenSetMapping[_msgSender()];
        if (tokenSet.remove(tokenId)) {
            surfVoucher.safeTransferFrom(address(this), _msgSender(), tokenId);

            emit StandbyCancelled(_msgSender(), tokenId);
        }
    }

    /// internal functions

    /**
     * return if outletId exists
     */
    function _exists(uint256 outletId) internal view returns (bool) {
        return outletIdSet.contains(outletId);
    }

    /**
     * calculate avaiable redit quota
     */
    function _calcAviaiableQuota(
        OutletData memory outletData
    ) internal pure returns (uint256) {
        return
            outletData.creditQuota > outletData.circulation
                ? outletData.creditQuota - outletData.circulation
                : 0;
    }

    function _setOutletDescriptor(IOutletDescriptor outletDescriptor_) internal {
        require(address(outletDescriptor_) != address(0), Errors.INVALID_INPUT);

        IOutletDescriptor previousDescriptor = outletDescriptor;
        outletDescriptor = outletDescriptor_;

        emit OutletDescriptorChanged(previousDescriptor, outletDescriptor);
    }

    /// Administrative functions

    /**
     * add new outLet
     */
    function addOutlet(
        string memory name,
        address manager,
        uint256 creditQuota
    ) external onlyOwner {
        require(manager != address(0), Errors.INVALID_INPUT);

        // update state
        uint256 outletId = _generateOutletId();
        outletIdSet.add(outletId);
        outletDataMapping[outletId] = OutletData({
            name: name,
            manager: manager,
            isActive: true,
            creditQuota: creditQuota,
            circulation: 0
        });

        emit AddedOutlet(outletId, name, manager, true, creditQuota);
    }

    /**
     * deactivate outLet
     */
    function deactivateOutlet(uint256 outletId) external onlyOwner {
        require(_exists(outletId), Errors.NONEXISTENCE);

        OutletData storage outletData = outletDataMapping[outletId];

        // update state
        if (outletData.isActive) {
            outletData.isActive = false;
            emit DeactivatedOutlet(outletId);
        }
    }

    /**
     * activate outLet
     */
    function activateOutlet(uint256 outletId) external onlyOwner {
        require(_exists(outletId), Errors.NONEXISTENCE);

        OutletData storage outletData = outletDataMapping[outletId];

        // update state
        if (!outletData.isActive) {
            outletData.isActive = true;
            emit ActivatedOutlet(outletId);
        }
    }

    /**
     * set credit quota
     */
    function setCreditQuota(
        uint256 outletId,
        uint256 creditQuota_
    ) external onlyOwner {
        require(_exists(outletId), Errors.NONEXISTENCE);

        OutletData storage outletData = outletDataMapping[outletId];

        // update state
        uint256 previousQuota = outletData.creditQuota;
        outletData.creditQuota = creditQuota_;

        emit OutletCreditQuotaChanged(
            outletId,
            previousQuota,
            outletData.creditQuota
        );
    }

    /**
     * remove outLet
     */
    function removeOutlet(uint256 outletId) external onlyOwner {
        require(_exists(outletId), Errors.NONEXISTENCE);

        OutletData memory outletData = outletDataMapping[outletId];
        require(outletData.circulation == 0, Errors.ILLEGAL_STATE);

        // update state
        delete outletDataMapping[outletId];
        outletIdSet.remove(outletId);

        emit RemovedOutlet(outletId);
    }

    /**
     * set outlet name
     */
    function setName(uint256 outletId, string memory name) external onlyOwner {
        require(_exists(outletId), Errors.NONEXISTENCE);

        OutletData storage outletData = outletDataMapping[outletId];

        // update state
        string memory previousName = outletData.name;
        outletData.name = name;

        emit OutletNameChanged(outletId, previousName, name);
    }

    /**
     * set outlet manager
     */
    function setManager(uint256 outletId, address manager) external onlyOwner {
        require(_exists(outletId), Errors.NONEXISTENCE);
        require(manager != address(0), Errors.INVALID_INPUT);

        OutletData storage outletData = outletDataMapping[outletId];

        // update state
        address previousManager = outletData.manager;
        outletData.manager = manager;

        emit OutletManagerChanged(outletId, previousManager, manager);
    }

    /**
     * set OutletDescriptor
     */
    function setOutletDescriptor(IOutletDescriptor outletDescriptor_) external onlyOwner {
        _setOutletDescriptor(outletDescriptor_);
    }
}

