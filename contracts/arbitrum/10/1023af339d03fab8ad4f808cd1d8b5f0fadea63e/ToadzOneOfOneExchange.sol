//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ToadzOneOfOneExchangeContracts.sol";

contract ToadzOneOfOneExchange is Initializable, ToadzOneOfOneExchangeContracts {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    function initialize() external initializer {
        ToadzOneOfOneExchangeContracts.__ToadzOneOfOneExchangeContracts_init();
    }

    function addRecipients(
        address[] calldata _recipients,
        ToadTraits[] calldata _traits)
    external
    onlyAdminOrOwner
    {
        require(_recipients.length > 0 && _recipients.length == _traits.length, "ToadzOneOfOneExchange: Bad recipient lengths");

        for(uint256 i = 0; i < _recipients.length; i++) {
            require(!oneOfOneRecipients.contains(_recipients[i]), "ToadzOneOfOneExchange: Recipient already exists");
            require(_traits[i].rarity == ToadRarity.ONE_OF_ONE, "ToadzOneOfOneExchange: Rarity must be 1-of-1");

            oneOfOneRecipients.add(_recipients[i]);

            recipientToTraits[_recipients[i]] = _traits[i];
        }
    }

    function claimOneOfOne(
        uint256 _sacrificialToadId)
    external
    whenNotPaused
    onlyEOA
    contractsAreSet
    {
        require(_sacrificialToadId > 0, "ToadzOneOfOneExchange: Bad sacrificial toad ID");
        require(oneOfOneRecipients.contains(msg.sender), "ToadzOneOfOneExchange: Not a one of one recipient");
        require(!recipientToHasClaimed[msg.sender], "ToadzOneOfOneExchange: Already claimed");
        require(toadz.ownerOf(_sacrificialToadId) == msg.sender, "ToadzOneOfOneExchange: Sacrificial toad does not belong to caller");

        recipientToHasClaimed[msg.sender] = true;

        toadz.burn(_sacrificialToadId);

        toadz.mint(msg.sender, recipientToTraits[msg.sender]);
    }

    function getAllRecipients() external view returns(address[] memory) {
        return oneOfOneRecipients.values();
    }
}
