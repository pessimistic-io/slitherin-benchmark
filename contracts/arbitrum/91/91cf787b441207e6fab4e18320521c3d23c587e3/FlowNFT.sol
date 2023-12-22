// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Strings } from "./Strings.sol";
import { IConstantFlowAgreementV1 } from "./IConstantFlowAgreementV1.sol";
import { ISuperfluid, ISuperToken } from "./ISuperfluid.sol";

import { IConstantFlowAgreementHook } from "./IConstantFlowAgreementHook.sol";
import { ISuperfluidToken } from "./ISuperfluid.sol";

/*
* NFT representing a flow that points to offchain data, created by CFAv1 hook or manual minting.
* The existence of a CFA flow doesn't guarantee the existence of a representing token.
* There's a mint method which allows anybody to retroactively mint a token for an existing flow.
*/
contract FlowNFT is IConstantFlowAgreementHook {

    using Strings for uint256;

    struct FlowData {
        address token;
        address sender;
        address receiver;
        uint64 startDate;
    }

    /// thrown by methods not available, e.g. transfer
    error NOT_AVAILABLE();

    /// thrown when attempting to mint an NFT which already exists
    error ALREADY_MINTED();

    /// thrown when looking up a token or flow which doesn't exist
    error NOT_EXISTS();

    /// thrown when trying to mint to the zero address
    error ZERO_ADDRESS();

    // thrown when trying to burn a token representing an ongoing flow
    error FLOW_ONGOING();

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    string public name;
    string public symbol;
    string public constant baseUrl = "https://nft.superfluid.finance/cfa/v1/getmeta";

    // incremented on every new mint and used as tokenId
    uint256 public tokenCnt;

    mapping(uint256 => FlowData) internal _flowDataById;
    mapping(bytes32 => uint256) internal _idByFlowKey;

    IConstantFlowAgreementV1 immutable internal _cfaV1;

    constructor(address cfa_, string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
        _cfaV1 = IConstantFlowAgreementV1(cfa_);
    }

    /// Allows retroactive minting to flow receivers if minting wasn't done via the hook.
    /// Can be triggered by anybody.
    function mint(address token, address sender, address receiver) public returns(bool) {
        int96 flowRate = _getFlowRate(token, sender, receiver);
        if(flowRate > 0) {
            _mint(token, sender, receiver, 0);
            return true;
        } else {
            revert NOT_EXISTS();
        }
    }

    /// Allows tokens not "covered" by an active flow to be burned
    function burn(address token, address sender, address receiver) public returns(bool) {
        // revert if no token exists
        getTokenId(token, sender, receiver);
        if(_getFlowRate(token, sender, receiver) == 0) {
            _burn(token, sender, receiver);
            return true;
        } else {
            revert FLOW_ONGOING();
        }
    }

    /// returns the token id representing the given flow
    /// reverts if no token exist
    /// note that this method doesn't check if an actual flow currently exists for this params (flowrate != 0)
    function getTokenId(address token, address sender, address receiver) public view returns(uint256 tokenId) {
        bytes32 flowKey = keccak256(abi.encodePacked(
                token,
                sender,
                receiver
            ));
        tokenId = _idByFlowKey[flowKey];
        if(tokenId == 0) revert NOT_EXISTS();
    }

    // ============= IConstantFlowAgreementHook interface =============

    function onCreate(ISuperfluidToken token, CFAHookParams memory newFlowData) public override returns(bool) {
        _mint(address(token), newFlowData.sender, newFlowData.receiver, uint64(block.timestamp));
        return true;
    }

    function onUpdate(ISuperfluidToken /*token*/, CFAHookParams memory /*updatedFlowData*/, int96 /*oldFlowRate*/) public override pure returns(bool) {
        return true;
    }

    function onDelete(ISuperfluidToken token, CFAHookParams memory updatedFlowData, int96 /*oldFlowRate*/) public override returns(bool) {
        _burn(address(token), updatedFlowData.sender, updatedFlowData.receiver);
        return true;
    }

    // ============= ERC721 interface =============

    function ownerOf(uint256 id) public view virtual returns (address owner) {
        owner = _flowDataById[id].receiver;
        if(owner == address(0)) revert NOT_EXISTS();
    }

    /// note that we can't rely on the startDate as a flow may have been deleted and re-crated in the meantime
    function tokenURI(uint256 id) public view returns (string memory) {
        FlowData memory flowData = _flowDataById[id];

        address receiver = ownerOf(id);
        return string(abi.encodePacked(
            baseUrl,
            '?chain_id=', block.chainid.toString(),
            '&token_address=', Strings.toHexString(uint256(uint160(flowData.token)), 20),
            '&token_symbol=', ISuperToken(flowData.token).symbol(),
            '&token_decimals=', uint256(ISuperToken(flowData.token).decimals()).toString(),
            '&sender=', Strings.toHexString(uint256(uint160(flowData.sender)), 20),
            '&receiver=', Strings.toHexString(uint256(uint160(receiver)), 20),
            '&flowRate=',uint256(uint96(_getFlowRate(flowData.token, flowData.sender, receiver))).toString(),
            flowData.startDate == 0 ? '' : '&start_date=',uint256(flowData.startDate).toString()
        ));
    }

    // always returns 1 in order to not waste storage
    function balanceOf(address owner) public view virtual returns (uint256) {
        if(owner == address(0)) revert ZERO_ADDRESS();
        return 1;
    }

    // ERC165 Interface Detection
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // Interface ID for ERC165
            interfaceId == 0x80ac58cd || // Interface ID for ERC721
            interfaceId == 0x5b5e139f; // Interface ID for ERC721Metadata
    }

    function approve(address /*spender*/, uint256 /*id*/) public pure {
        revert NOT_AVAILABLE();
    }

    function setApprovalForAll(address /*operator*/, bool /*approved*/) public pure {
        revert NOT_AVAILABLE();
    }

    function transferFrom(address /*from*/, address /*to*/, uint256 /*id*/) public pure {
        revert NOT_AVAILABLE();
    }

    function safeTransferFrom(address /*from*/, address /*to*/, uint256 /*id*/) public pure {
        revert NOT_AVAILABLE();
    }

    function safeTransferFrom(address /*from*/, address /*to*/, uint256 /*id*/, bytes calldata /*data*/) public pure {
        revert NOT_AVAILABLE();
    }

    // ============= private interface =============

    function _mint(address token, address sender, address receiver, uint64 startDate) internal {
        if(receiver == address(0)) revert ZERO_ADDRESS();
        uint256 id = ++tokenCnt;
        bytes32 flowKey = keccak256(abi.encodePacked(
                token,
                sender,
                receiver
            ));
        if(_idByFlowKey[flowKey] != 0) revert ALREADY_MINTED();
        if(_flowDataById[id].receiver != address(0)) revert ALREADY_MINTED();
        _flowDataById[id] = FlowData(token, sender, receiver, startDate);
        _idByFlowKey[flowKey] = id;
        emit Transfer(address(0), receiver, id);
    }

    function _burn(address token, address sender, address receiver) internal {
        bytes32 flowKey = keccak256(abi.encodePacked(token, sender, receiver));
        uint256 id = _idByFlowKey[flowKey];
        if(id == 0) revert NOT_EXISTS();
        delete _flowDataById[id];
        delete _idByFlowKey[flowKey];
        emit Transfer(receiver, address(0), id);
    }

    function _getFlowRate(address token, address sender, address receiver) internal view returns(int96 flowRate) {
        (,flowRate,,) = _cfaV1.getFlow(ISuperToken(token), sender, receiver);
    }
}
