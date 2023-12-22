// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma abicoder v2;

import "./NonblockingLzApp.sol";
import "./ERC721.sol";
import "./Counters.sol";

/// @title A LayerZero example sending a cross chain message from a source chain to a destination chain to increment a counter
contract crossChainNft is NonblockingLzApp, ERC721 {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    uint16 internal _dstChainId = 110;

    mapping(address => uint256) public preApprove;
    uint64 public nonceP;
    uint16 public srcChainIdP;
    bytes public srcAddressP;
    bytes public payloadP;

    bool internal active;

    constructor(
        address _lzEndpoint
    ) NonblockingLzApp(_lzEndpoint) ERC721("Clip", "CLP") {}

    // @notice LayerZero endpoint will invoke this function to deliver the message on the destination
    // @param _srcChainId - the source endpoint identifier
    // @param _srcAddress - the source sending contract address from the source chain
    // @param _nonce - the ordered message nonce
    // @param _payload - the signed payload is the UA bytes has encoded to be sent

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal override {
        srcChainIdP = _srcChainId;
        _srcAddress = srcAddressP;
        nonceP = _nonce;
        payloadP = _payload;

        if (active) {
            (uint256 amount, address who) = decode(_payload);
            preApprove[who] = amount;
            for (uint i = 0; i < amount; i++) {
                mint(who);
            }
        }
    }

    function changeActiveT() public {
        active = true;
    }

    function changeActiveF() public {
        active = false;
    }

    function getPreApproved(
        uint256 _amount,
        bytes memory adapterParams
    ) public payable {
        require(_amount < 10, "TOO MUCH BRO");
        bytes memory encodedData = encode(_amount, msg.sender);

        _lzSend(
            _dstChainId,
            encodedData,
            payable(msg.sender),
            address(0x0),
            adapterParams,
            msg.value
        );
    }

    function sending(
        uint16 _dstChainIdS,
        bytes calldata _payload,
        bytes calldata _adapterParams
    ) external payable {
        _lzSend(
            _dstChainIdS,
            _payload,
            payable(msg.sender),
            address(0x0),
            _adapterParams,
            msg.value
        );
    }

    function setOracle(uint16 dstChainId, address oracle) external onlyOwner {
        uint TYPE_ORACLE = 6;
        // set the Oracle
        lzEndpoint.setConfig(
            lzEndpoint.getSendVersion(address(this)),
            dstChainId,
            TYPE_ORACLE,
            abi.encode(oracle)
        );
    }

    function mint(address to) internal returns (uint256) {
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _mint(to, newItemId);
        return newItemId;
    }

    function encode(
        uint256 nr,
        address addr
    ) public pure returns (bytes memory) {
        return abi.encodePacked(nr, addr);
    }

    function decode(bytes memory data) public pure returns (uint256, address) {
        uint256 nr;
        address addr;

        assembly {
            nr := mload(add(data, 32))
            addr := mload(add(data, 52))
        }

        return (nr, addr);
    }
}

