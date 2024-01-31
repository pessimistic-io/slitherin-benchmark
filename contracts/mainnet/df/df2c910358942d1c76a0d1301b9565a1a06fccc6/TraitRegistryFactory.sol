// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./CommunityList.sol";
import "./CommunityRegistry.sol";
import "./TheProxy.sol";
import "./IRegistryConsumer.sol";
import "./ECRegistryV3c.sol";
import "./BlackHolePrevention.sol";
import "./Ownable.sol";

// import "hardhat/console.sol";

contract TraitRegistryFactory is Ownable, BlackHolePrevention {
    using Strings  for uint32; 

    bytes32              constant    public COMMUNITY_REGISTRY_ADMIN = keccak256("COMMUNITY_REGISTRY_ADMIN");

    event TraitRegistryAdded(uint32 _communityId, address _traitRegistry, uint32 _tokenNum);

    function deploy(
        uint32 _communityId,
        uint32 _tokenNum
    ) external returns (address) {

        // Get Galaxis registry
        IRegistryConsumer GalaxisRegistry = IRegistryConsumer(0x1e8150050A7a4715aad42b905C08df76883f396F);

        // Validate if this contract is the current version to be used. Else fail
        address TraitRegistryFactoryAddr = GalaxisRegistry.getRegistryAddress("TRAIT_REGISTRY_FACTORY");
        require(TraitRegistryFactoryAddr == address(this), "TraitRegistryFactory: Not current TraitRegistry factory");

        // Get the community_list contract
        CommunityList COMMUNITY_LIST = CommunityList(GalaxisRegistry.getRegistryAddress("COMMUNITY_LIST"));
        // Get the community data
        (,address crAddr,) = COMMUNITY_LIST.communities(_communityId);
        require(crAddr != address(0), "TraitRegistryFactory: Invalid community ID");
        // Get community registry
        CommunityRegistry thisCommunityRegistry = CommunityRegistry(crAddr);

        // Check if caller is the community owner
        // require(msg.sender == thisCommunityRegistry.community_admin(),"TraitRegistryFactory: Only community admin may deploy TraitRegistry");
        require(thisCommunityRegistry.isUserCommunityAdmin(COMMUNITY_REGISTRY_ADMIN, msg.sender), "TraitRegistryFactory: Community not owned by sender");

        // Check if the token contract we link this trait registry is valid
        require(thisCommunityRegistry.getRegistryAddress(
                    string(abi.encodePacked("TOKEN_", _tokenNum.toString()))
                )
            != address(0), "TraitRegistryFactory: Invalid token number to link with");

        // Launch new registry contract via proxy
        address LOOKUPAddr = GalaxisRegistry.getRegistryAddress("LOOKUP");
        TheProxy trait_proxy = new TheProxy("GOLDEN_TRAIT_REGISTRY", LOOKUPAddr);   // All golden contracts should start with `GOLDEN_`
        ECRegistryV3c traitRegistry = ECRegistryV3c(address(trait_proxy));
        traitRegistry.init(_communityId, msg.sender);                // To initialise owner

        // Write trait registry address to community registry
        thisCommunityRegistry.setRegistryAddress(
            string(abi.encodePacked("TRAIT_REGISTRY_", _tokenNum.toString())),
            address(traitRegistry)
        );

        emit TraitRegistryAdded(_communityId, address(traitRegistry), _tokenNum);

        return address(traitRegistry);
    }
}
