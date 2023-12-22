// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {NFT} from "./NFT.sol";
import {Auth, Authority, RolesAuthority} from "./RolesAuthority.sol";

contract Issuer is Auth {
    uint256 public defaultVendorFee = 5e15; // 0.005 ETH
    uint256 public defaultCutBps = 1500; // 15% cut
    uint256 public defaultFee = 1e15; // 0.001 ETH

    struct MintParams {
        uint256 tier;
        uint256 count;
    }

    struct BundleMintParams {
        NFT nft;
        MintParams[] tiers;
    }

    struct VendorFee {
        bool noFlatFee;
        uint64 flatFee;
    }

    struct ProtocolFee {
        bool noFlatFee;
        uint64 flatFee;
        bool noCut;
        uint64 cutBps;
    }

    event SetDefaultFees(uint256 defaultVendorFee, uint256 defaultCutBps, uint256 defaultFee);
    event SetVendorFees(address indexed collection, uint256 tier, uint256 fee);
    event SetProtocolFees(address indexed collection, uint256 tier, uint256 fee, uint256 cut);

    mapping(address user => uint256 balance) public accumulatedFees;
    mapping(NFT collection => mapping(uint256 tier => VendorFee VendorFee)) internal _vendorFees;
    mapping(NFT collection => mapping(uint256 tier => ProtocolFee ProtocolFee)) internal _protocolFees;

    constructor(address _owner, Authority _authority) Auth(_owner, _authority) {}

    function deployCollection(
        string memory name,
        string memory symbol,
        address controller,
        string memory baseTokenURI,
        uint256 maxSupply,
        uint256 transferFee
    ) external returns (NFT collection) {
        RolesAuthority authority = new RolesAuthority(address(this), Authority(address(0)));
        collection = new NFT(name, symbol, owner, address(authority), baseTokenURI, maxSupply, transferFee);
        // Role 0 has full control over the collection.
        authority.setRoleCapability(0, address(collection), NFT.setTransferFee.selector, true);
        authority.setRoleCapability(0, address(collection), NFT.setTierSupply.selector, true);
        authority.setRoleCapability(0, address(collection), NFT.setBaseURI.selector, true);
        authority.setRoleCapability(0, address(collection), NFT.setMaxSupply.selector, true);
        authority.setRoleCapability(0, address(collection), NFT.mint.selector, true);
        authority.setRoleCapability(0, address(collection), NFT.collectFees.selector, true);
        authority.setRoleCapability(0, address(this), this.setVendorFee.selector, true);
        // Role 1 has minting rights.
        authority.setRoleCapability(1, address(collection), NFT.mint.selector, true);
        authority.setUserRole(controller, 0, true);
        authority.setUserRole(controller, 1, true);
        authority.setUserRole(address(this), 1, true);
        authority.setOwner(owner);
    }

    function getFees(NFT collection, uint256 tier, uint256 count)
        public
        view
        returns (uint256 totalAmount, uint256 protocolAmount, uint256 vendorAmount)
    {
        ProtocolFee memory protocolFees = _protocolFees[collection][tier];
        VendorFee memory vendorFees = _vendorFees[collection][tier];
        uint256 baseFee = _getValue(protocolFees.noFlatFee, protocolFees.flatFee, defaultFee);
        uint256 vendorFee = _getValue(vendorFees.noFlatFee, vendorFees.flatFee, defaultVendorFee);
        uint256 cutBps = _getValue(protocolFees.noCut, protocolFees.cutBps, defaultCutBps);
        totalAmount = count * (baseFee + vendorFee);
        uint256 cut = vendorFee * cutBps / 10000;
        protocolAmount = count * (baseFee + cut);
        vendorAmount = count * (vendorFee - cut);
    }

    function setDefaultFees(uint256 _defaultVendorFee, uint256 _defaultCutBps, uint256 _defaultFee)
        external
        requiresAuth
    {
        defaultVendorFee = _defaultVendorFee;
        defaultCutBps = _defaultCutBps;
        defaultFee = _defaultFee;
        emit SetDefaultFees(_defaultVendorFee, _defaultCutBps, _defaultFee);
    }

    function setProtocolFee(NFT collection, uint256 tier, uint64 flatFee, uint64 cutBps) external requiresAuth {
        bool noFlatFee = flatFee == 0;
        bool noCut = cutBps == 0;
        _protocolFees[collection][tier] = ProtocolFee(noFlatFee, flatFee, noCut, cutBps);
        emit SetProtocolFees(address(collection), tier, flatFee, cutBps);
    }

    function setVendorFee(NFT collection, uint256 tier, uint64 fee) external {
        require(collection.authority().canCall(msg.sender, address(this), msg.sig), "Unauthorized");
        _vendorFees[collection][tier] = VendorFee(fee == 0, fee);
    }

    function mintToken(NFT collection, address recipient, uint256 tier, uint256 count)
        external
        payable
        returns (uint256[] memory tokenIds)
    {
        (uint256 fee, uint256 protocolFee, uint256 vendorFee) = getFees(collection, tier, count);
        require(msg.value >= fee, "Not enough ETH sent.");
        accumulatedFees[owner] += protocolFee;
        accumulatedFees[collection.owner()] += vendorFee;
        tokenIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokenIds[i] = collection.mint(recipient, tier);
        }
    }

    function _getValue(bool isZero, uint256 value, uint256 defaultValue) internal pure returns (uint256) {
        if (isZero) {
            return 0;
        } else if (value == 0) {
            return defaultValue;
        } else {
            return value;
        }
    }

    function collectFees() external {
        uint256 amount = accumulatedFees[msg.sender];
        accumulatedFees[msg.sender] = 0;
        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
    }
}

