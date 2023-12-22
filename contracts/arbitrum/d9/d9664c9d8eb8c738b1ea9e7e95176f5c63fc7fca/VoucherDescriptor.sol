// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

/**
 * @dev Contract based on:
 * https://github.com/solv-finance/solv-v2-ivo/blob/main/vouchers/convertible-voucher/contracts/ConveritbleVoucherDescriptor.sol
 */
import "./Ownable2Step.sol";
import "./IVNFTDescriptor.sol";
import "./IVoucherSVG.sol";
import "./ISurfVoucher.sol";
import "./StringConverter.sol";
import "./Base64.sol";

contract VoucherDescriptor is IVNFTDescriptor, Ownable2Step {
    using StringConverter for address;
    using StringConverter for uint256;
    using StringConverter for bytes;

    struct SlotMeta {
        string name;
        string desc;
        string externalUrl;
        IVoucherSVG voucherSvg;
    }

    // storage

    // SurfVoucher
    ISurfVoucher public surfVoucher;

    // contract description
    string public contractDesc;

    // slot -> SlotMeta mapping
    mapping(uint256 => SlotMeta) private slotMetaMapping;

    /// events

    constructor(
        ISurfVoucher _surfVoucher,
        address initOwner
    ) {
        require(address(_surfVoucher) != address(0), "Bad voucher address");
        require(initOwner != address(0), "Bad owner address");

        surfVoucher = _surfVoucher;
        _transferOwnership(initOwner);
    }

    /// Admin Functions

    /**
     * @notice Admin restricted function to set description for voucher contract
     */
    function setContractDesc(string memory _contractDesc) public onlyOwner {
        contractDesc = _contractDesc;
    }

    /**
     * @notice Admin restricted function to set address for VoucherSVG contract
     */
    function setVoucherSVG(
        uint256 _slot,
        IVoucherSVG _voucherSVG
    ) public onlyOwner {
        SlotMeta storage meta = slotMetaMapping[_slot];
        meta.voucherSvg = _voucherSVG;
    }

    /**
     * @notice Admin restricted function to set name for slot
     */
    function setSlotName(
        uint256 _slot,
        string memory _name
    ) public onlyOwner {
        SlotMeta storage meta = slotMetaMapping[_slot];
        meta.name = _name;
    }

    /**
     * @notice Admin restricted function to set description for slot
     */
    function setSlotDesc(
        uint256 _slot,
        string memory _desc
    ) public onlyOwner {
        SlotMeta storage meta = slotMetaMapping[_slot];
        meta.desc = _desc;
    }

    /**
     * @notice Admin restricted function to set external url for slot
     */
    function setSlotExternalUrl(
        uint256 _slot,
        string memory _externalUrl
    ) public onlyOwner {
        SlotMeta storage meta = slotMetaMapping[_slot];
        meta.externalUrl = _externalUrl;
    }

    /**
     * @notice Admin restricted function to set metadata for slot
     */
    function setSlotMeta(
        uint256 _slot,
        SlotMeta memory _slotMeta
    ) public onlyOwner {
        slotMetaMapping[_slot] = _slotMeta;
    }

    /// View Functions

    function getSlotMeta(uint256 _slot) external view returns (SlotMeta memory) {
        return slotMetaMapping[_slot];
    }

    function contractURI() external view override returns (string memory) {
        return
            string(
                abi.encodePacked(
                    'data:application/json;{"name":"',
                    surfVoucher.name(),
                    '","symbol":"',
                    surfVoucher.symbol(),
                    '","description":"',
                    _contractDescription(),
                    '","unitDecimals":"',
                    uint256(surfVoucher.unitDecimals()).toString(),
                    '","attributes":{}}'
                )
            );
    }

    function slotURI(
        uint256 _slot
    ) external view override returns (string memory) {
        SlotMeta memory meta = slotMetaMapping[_slot];

        return
            string(
                abi.encodePacked(
                    'data:application/json;{"name":"',
                    meta.name,
                    '","unitsInSlot":"',
                    surfVoucher.unitsInSlot(_slot).toString(),
                    '","tokensInSlot":"',
                    surfVoucher.tokensInSlot(_slot).toString(),
                    '","description":"',
                    _slotDescription(_slot),
                    '","external_url":"',
                    meta.externalUrl,
                    '","attributes":{}}'
                )
            );
    }

    function tokenURI(
        uint256 _tokenId
    ) external view override returns (string memory) {
        uint256 slotId = surfVoucher.slotOf(_tokenId);
        SlotMeta memory meta = slotMetaMapping[slotId];

        bytes memory name = abi.encodePacked(meta.name, " #", _tokenId.toString());
        uint256 units = surfVoucher.unitsInToken(_tokenId);

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        abi.encodePacked(
                            '{"name":"',
                            name,
                            '","description":"',
                            _tokenDescription(_tokenId),
                            // '","image":"data:image/svg+xml;base64,',
                            // Base64.encode(meta.voucherSvg.generateSVG(address(surfVoucher), _tokenId)),
                            '","image_data":"data:image/svg+xml;base64,',
                            Base64.encode(meta.voucherSvg.generateSVG(address(surfVoucher), _tokenId)),
                            // '","units":"',
                            // units.toString(),
                            // '","slot":"',
                            // slotId.toString(),
                            '","external_url":"',
                            meta.externalUrl,
                            '","attributes":[',
                            abi.encodePacked(
                                _buildTrait( "slot", slotId.toString(), "slot that this token belongs", "string", 1),
                                ",",
                                _buildTrait("unitDecimals", uint256(surfVoucher.unitDecimals()).toString(), "unit decimals", "string", 2),
                                ",",
                                _buildTrait("units", string(_formatValue(units, 2).trim(3)), "units in this token", "string", 3)),
                            "]}"
                    )
                )
            ));
    }

    /// Internal functions
    function _contractDescription() private view returns (bytes memory) {
        return abi.encodePacked(contractDesc);
    }

    function _slotDescription(
        uint256 _slot
    ) private view returns (bytes memory) {
        SlotMeta memory meta = slotMetaMapping[_slot];

        if (bytes(meta.desc).length > 0) {
            return
                abi.encodePacked(
                    meta.desc,
                    "\\n\\n",
                    _contractDescription()
                );
        } else {
            return _contractDescription();
        }
    }

    function _tokenDescription(
        uint256 _tokenId
    ) private view returns (bytes memory) {
        uint256 slotId = surfVoucher.slotOf(_tokenId);
        SlotMeta memory meta = slotMetaMapping[slotId];
        bytes memory units = _formatValue(surfVoucher.unitsInToken(_tokenId), surfVoucher.unitDecimals());

        return
            abi.encodePacked(
                meta.name,
                " with ",
                units,
                " units built-in.\\n\\n",
                _slotDescription(slotId)
            );
    }

    function _buildTrait(
        string memory traitName,
        string memory traitValue,
        string memory description,
        string memory displayType,
        uint256 displayOrder
    ) private pure returns (bytes memory data) {
        data = abi.encodePacked(
            "{",
            '"trait_type":"',
            traitName,
            '","value":"',
            traitValue,
            '","description":"',
            description,
            '","display_type":"',
            displayType,
            '","display_order":',
            displayOrder.toString(),
            "}"
        );
    }

    function _formatValue(uint256 value, uint8 decimals) private pure returns (bytes memory) {
        return value.uint2decimal(decimals).trim(decimals - 2).addThousandsSeparator();
    }
}

