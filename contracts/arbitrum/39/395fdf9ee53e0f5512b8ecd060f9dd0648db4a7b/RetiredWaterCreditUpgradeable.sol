// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./AccessControl.sol";
import "./Strings.sol";

import "./IMintersRegistry.sol";
import "./IRetiredWaterCredit.sol";
import "./IRH2O.sol";
import "./ERC721BaseUpgradeable.sol";

contract RetiredWaterCreditUpgradeable is
    ERC721BaseUpgradeable,
    IRetiredWaterCredit
{
    using Strings for uint256;

    IRH2O public rh2O;
    IMintersRegistry public mintersRegistry;

    mapping(uint => RetirementParams) public idToRetirementParams;

    bool public mintRestricted;

    address public rh2OExchange;

    bool public isEmergency;

    event MintRestrictionSet(bool mintRestricted);
    event ExchangeSet(address exchange);

    event EmergencyModeSet(bool isEmergency);

    function initialize(address _rh2O) public initializer {
        __ERC721Base__init("RetiredWaterCredit", "RETIREDWATERCREDIT");

        rh2O = IRH2O(_rh2O);
        mintersRegistry = IMintersRegistry(_rh2O);
        mintRestricted = true;
    }

    modifier notEmergency() {
        require(!isEmergency, "Emergency");
        _;
    }

    function retire(
        address from,
        address to,
        uint retiredAmount
    ) external notEmergency {
        require(
            _msgSender() == from || _msgSender() == rh2OExchange,
            "Not allowed"
        );
        if (mintRestricted) {
            require(mintersRegistry.isMinter(from), "Minter allowed");
        } else if (_msgSender() != rh2OExchange) {
            require(from == to, "Can't retire to another address");
        }

        require(rh2O.balanceOf(from) >= retiredAmount, "Insufficient balance");
        rh2O.burn(from, retiredAmount);

        _mint(to, 1);

        uint lastId = _totalMinted();

        if (mintRestricted) {
            idToRetirementParams[lastId].minter = from;
        }

        idToRetirementParams[lastId].from = from;
        idToRetirementParams[lastId].receiver = to;
        idToRetirementParams[lastId].amount = retiredAmount;
        idToRetirementParams[lastId].timestamp = block.timestamp;

        emit WaterCreditRetired(_totalMinted(), idToRetirementParams[lastId]);
    }

    function setMintRestricted(bool _isMintRestricted) external onlyOwner {
        mintRestricted = _isMintRestricted;
        emit MintRestrictionSet(mintRestricted);
    }

    function setRH2O(address _rh2O, address _registry) external onlyOwner {
        rh2O = IRH2O(_rh2O);
        mintersRegistry = IMintersRegistry(_registry);
    }

    function setEmergency(bool _isEmergency) external onlyOwner {
        isEmergency = _isEmergency;

        emit EmergencyModeSet(isEmergency);
    }

    function setRH2OExchange(address _exchange) external onlyOwner {
        rh2OExchange = _exchange;

        emit ExchangeSet(rh2OExchange);
    }

    function tokenURI(
        uint tokenId
    )
        public
        view
        virtual
        override(IERC721AUpgradeable, ERC721AUpgradeable)
        returns (string memory)
    {
        IMintersRegistry.MinterInfo memory minterInfo =  mintersRegistry
                .getMinterInfo(idToRetirementParams[tokenId].minter);

        string memory metadata = string.concat(
            '{"name":"Retired Water Credit","description":"This NFT represents a water credits offset produced through RH2O burning. For more information, visit https://www.wacomet.com","image":"ipfs://QmSej8wymWcg2kJE1vDi18wB7Kz4PEdwZhWHkawvSqxPDW","attributes":[{"trait_type":"Water producer","value":"',
            minterInfo.name,
            '"},{"trait_type":"Water producer address","value":"',
            toString(abi.encodePacked(idToRetirementParams[tokenId].minter)),
            '"},{"trait_type":"Receiver","value":"',
            toString(abi.encodePacked(idToRetirementParams[tokenId].receiver)),
            '"},{"trait_type":"Amount","value":"',
            idToRetirementParams[tokenId].amount.toString(),
            '"},{"trait_type":"Retirement timestamp","value":"',
            idToRetirementParams[tokenId].timestamp.toString(),
            '"},{"trait_type":"Retired from","value":"',
            toString(abi.encodePacked(idToRetirementParams[tokenId].from)),
            '"},{"trait_type":"Latitude","value":"',
            minterInfo.latitude,
            '"},{"trait_type":"Longitude","value":"',
            minterInfo.longitude,
            '"}]}'
        );

        return metadata;
    }

    function toString(bytes memory data) public pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint(uint8(data[i] >> 4))];
            str[3 + i * 2] = alphabet[uint(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }
}

