// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./NFT721Ticket.sol";
import "./ITicketCollectionFactory.sol";
import "./AccessControl.sol";


contract TicketCollectionFactory is AccessControl, ITicketCollectionFactory {

     modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "It is Not an admin role"
        );
        _;
    }
    
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function createTicketCollection(
        string memory _name,
        string memory _symbol,
        string memory _baseURI
    ) external override onlyAdmin returns (address) {
        NFT721Ticket nft721Ticket = new NFT721Ticket(_name, _symbol, _baseURI);

        changeOwnershipNFTContract(msg.sender,address(nft721Ticket));

        return address(nft721Ticket);

    }

    function changeOwnershipNFTContract(address _newOwner , address ticketCollectionAddress) internal {
        NFT721Ticket(ticketCollectionAddress).transferOwnership(_newOwner);
    }
    
}
