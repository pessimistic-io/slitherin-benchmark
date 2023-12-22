// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./NonblockingLzApp.sol";
import "./DAOAccessControlled.sol";
import "./IEntity.sol";
import "./ILoot8Token.sol";
import "./IDispatcher.sol";
import "./IEntityFactory.sol";
import "./ICollectible.sol";
import "./ITokenPriceCalculator.sol";
import "./ILayerZeroEndpoint.sol";

import "./Strings.sol";
import "./Counters.sol";
import "./ERC721.sol";
import "./ERC721URIStorage.sol";
import "./ERC721Enumerable.sol";

abstract contract Collectible is ICollectible, NonblockingLzApp, ERC721, ERC721URIStorage, ERC721Enumerable, DAOAccessControlled {
    
    using Counters for Counters.Counter;

    struct CollectibleData {
        // The Data URI where details for collectible will be stored in a JSON file
        string dataURI;
        string name;
        string symbol;
        Area area;
    }

    // Unique token IDs for new collectible NFTs minted to patrons
    Counters.Counter private collectibleIds;

    // Type of collectible(Passport, Offer, Digital Collectible or Badge)
    CollectibleType public collectibleType;

    // A collectible may optionally be linked to an entity
    // If its not then this will be address(0)
    address public entity;

    address loot8Token; // ERC20 Token address

    bool public isActive; // Flag to indicate if this collectible is active or expired

    // List of all collectibles linked to this collectible
    // Eg: An offer linked to a passport, digital collectible linked
    // to a passport,offer linked to digital collectible, badges linked to passport, etc.
    // Enforcement of dependancies will have to be done by contracts
    // implementing this abstract class
    address[] public linkedCollectibles;

    // Collectible ID => Collectible Attributes
    // A mapping that maps collectible ids to its details
    mapping(uint256 => CollectibleDetails) public collectibleDetails;

    CollectibleData public collectibleData;

    constructor(
        address _entity,
        CollectibleType _collectibleType,
        CollectibleData memory _collectibleData,
        address _authority,
        address _loot8Token,
        address _layerzeroEndpoint
    ) ERC721(_collectibleData.name, _collectibleData.symbol)
      NonblockingLzApp(_layerzeroEndpoint) {

        DAOAccessControlled._setAuthority(_authority);

        // Set the collectible type(Passport, Offer, Digital Collectible or Badge)
        collectibleType = _collectibleType;

        // Set the entity that this collectible may be linked to
        entity = _entity;
        
        // Set the collectible area/dataURI
        collectibleData = _collectibleData;

        // Set the DAO ERC20 token address
        loot8Token = _loot8Token;

        // Activate the collectible as soon as it is deployed
        isActive = true;

        collectibleIds.increment(); // Start from 1 as id == 0 is a check for existence

    }

    /**
     * @notice Mints a collectible NFT to patron when they meet the specified criteria
     * @notice A mapping maps each Collectible NFT ID to its details
     * @param _patron address Patrons wallet address
     * @param _expiry uint256 Expiry timestamp for the nft
     * @param _transferable bool Flag to indicate if the nft can be transferred to another wallet
     * @return newCollectibleId uint256 ID for the newly minted NFT
    */
    function _mint (
        address _patron,
        uint256 _expiry,
        bool _transferable
    ) internal virtual returns (uint256 newCollectibleId)
    {

        // Check if the collectible is active
        require(isActive, "Collectible no longer offered");

        // Assign a unique ID to the new collectible NFT to be minted
        newCollectibleId = collectibleIds.current();

        // Mint the collectible NFT to the patron
        _mint(_patron, newCollectibleId);

        // Add details about the collectible to the collectibles object and add it to the mapping
        collectibleDetails[newCollectibleId] = CollectibleDetails({
            id: newCollectibleId,
            mintTime: block.timestamp, 
            expiry: _expiry,
            isActive: true,
            transferable: _transferable,
            rewardBalance: 0,
            visits: 0,
            friendVisits: 0,
            redeemed: false
        });

        // Increment ID for next collectible NFT
        collectibleIds.increment();

        // Emit an event for collectible NFT minting with details
        emit CollectibleMinted(newCollectibleId, _patron, _expiry, _transferable, collectibleData.dataURI);
    }

    /**
     * @notice Activation/Deactivation of a Collectible NFT token
     * @param _collectibleId uint256 Collectible ID to be toggled
     * @return _status bool Status of the NFT after toggling
    */
    function _toggle(uint256 _collectibleId) internal virtual returns(bool _status) {

        // Check if collectible is active
        require(isActive, "Collectible no longer offered");

         // Check if collectible NFT with the given Id exists
        require(collectibleDetails[_collectibleId].id != 0, "No such collectible");

        // Toggle the collectible NFT
        collectibleDetails[_collectibleId].isActive = !collectibleDetails[_collectibleId].isActive;

        // Poll the status
        _status = collectibleDetails[_collectibleId].isActive;

        // Emit an event for collectible NFT toggling with status
        emit CollectibleToggled(_collectibleId, _status);
    }

    /**
     * @notice Called when the entity offering the collectible wishes to retire it.
     * @notice The Collectible NFTs minted to patron stay with them as memorablia.
     * @notice Any functionality on the collectible will be blocked forever
     * @notice Retire collectibles are permanantly retired and can never be re-activated again
     * @notice Can only be called once
    */
    function _retire() internal virtual {
        require(isActive, "Collectible already discontinued");
        isActive = false;

        emit RetiredCollectible(address(this));
    }

    /**
     * @notice Transfers reward tokens to the patrons wallet when they purchase drinks/products.
     * @notice Internally also maintains and updates a tally around number of rewards held by a patron.
     * @notice Should be called when the bartender serves an order and receives payment for the drink.
     * @param _patron address Patrons wallet address
     * @param _amount uint256 Amount of rewards to be credited
    */
    function _creditRewards(address _patron, uint256 _amount) internal virtual {

        // Check if collectible is active
        require(isActive, "Collectible Retired");

        // Get the Collectible NFT ID for the patron
        uint256 collectibleId = tokenOfOwnerByIndex(_patron, 0);

        // Check if the patrons collectible is active
        require(collectibleDetails[tokenOfOwnerByIndex(_patron, 0)].isActive, "Collectible suspended");

        // Update a tally for reward balance in a collectible
        collectibleDetails[collectibleId].rewardBalance = 
                    collectibleDetails[collectibleId].rewardBalance + int256(_amount);

        // Emit an event for reward credits to collectible with relevant details
        emit CreditRewardsToCollectible(collectibleId, _patron, _amount);
    }

    /**
     * @notice Burns reward tokens from patrons wallet when they redeem rewards for free drinks/products.
     * @notice Internally also maintains and updates a tally around number of rewards held by a patron.
     * @notice Should be called when the bartender serves an order in return for reward tokens as payment.
     * @param _patron address Patrons wallet address
     * @param _amount uint256 Expiry timestamp for the nft
    */
    function _debitRewards(address _patron, uint256 _amount) internal virtual {

        // Check if collectible is active
        require(isActive, "Collectible Retired");
        
        // Get the Collectible NFT ID for the patron
        uint256 collectibleId = tokenOfOwnerByIndex(_patron, 0);

        // Check if the patrons collectible is active
        require(collectibleDetails[collectibleId].isActive, "Collectible suspended");

        // Update a tally for reward balance in a collectible
        collectibleDetails[collectibleId].rewardBalance = 
                    collectibleDetails[collectibleId].rewardBalance - int256(_amount);
        
        // Emit an event for reward debits from a collectible with relevant details
        emit BurnRewardsFromCollectible(collectibleId, _patron, _amount);
    }

    /**
     * @notice Credits visits to patrons passport
     * @notice Used as a metric to determine eligibility for special NFT airdrops
     * @notice Should be called by the mobile app whenever the patron visits the club
     * @notice Only used for passport Collectible types
     * @param _collectibleId uint256 collectible id to which the visit needs to be added
    */
    function _addVisit(uint256 _collectibleId) internal virtual {

        // Check if collectible is active
        require(isActive, "Collectible Retired");

        // Check if collectible NFT with the given Id exists
        require(collectibleDetails[_collectibleId].id != 0, "No such collectible");

        // Check if patron collectible is active or disabled
        require(collectibleDetails[_collectibleId].isActive, "Collectible suspended");

        // Credit visit to the collectible
        collectibleDetails[_collectibleId].visits = collectibleDetails[_collectibleId].visits + 1;

        // Emit an event marking a collectible holders visit to the club
        emit Visited(_collectibleId);
    }

    /**
     * @notice Credits friend visits to patrons collectible
     * @notice Used as a metric to determine eligibility for special NFT airdrops
     * @notice Should be called by the mobile app whenever a friend of the patron
     * @notice holding collectible with given ID visits the club
     * @param _collectibleId uint256 collectible id to which the visit needs to be added
    */
    function _addFriendsVisit(uint256 _collectibleId) internal virtual {

        // Check if collectible is active
        require(isActive, "Collectible Retired");

        // Check if collectible NFT with the given Id exists
        require(collectibleDetails[_collectibleId].id != 0, "No such collectible");

        // Check if patron collectible is active or disabled
        require(collectibleDetails[_collectibleId].isActive, "Collectible suspended");

        // Credit a friend visit to the collectible
        collectibleDetails[_collectibleId].friendVisits = collectibleDetails[_collectibleId].friendVisits + 1;

        // Emit an event marking a collectible holders friends visit to the club
        emit FriendVisited(_collectibleId);
    }

    function _linkCollectible(address _collectible) internal virtual {
        linkedCollectibles.push(_collectible);

        // Emit an event marking a collectible holders friends visit to the club
        emit CollectiblesLinked(address(this), _collectible);
    }

    function _delinkCollectible(address _collectible) internal virtual {
         for(uint256 i = 0; i < linkedCollectibles.length; i++) {
            if (linkedCollectibles[i] == _collectible) {
                // delete linkedCollectibles[i];
                if(i < linkedCollectibles.length-1) {
                    linkedCollectibles[i] = linkedCollectibles[linkedCollectibles.length-1];
                }
                linkedCollectibles.pop();
                break;
            }
        }
        emit CollectiblesDelinked(address(this), _collectible);
    }

    function _updateDataURI(string memory _dataURI) internal virtual {

        // Check if collectible is active
        require(isActive, "Collectible Retired");
        
        string memory oldDataURI = collectibleData.dataURI;
        
        collectibleData.dataURI = _dataURI;

        // Emit an event for updation of dataURI
        emit DataURIUpdated(address(this), oldDataURI, collectibleData.dataURI);
    }

    function _calculateRewards(uint256 _price) internal virtual returns(uint256) {
        return (_price * (10**ILoot8Token(loot8Token).decimals())) / 
                ITokenPriceCalculator(IDispatcher(IDAOAuthority(authority).dispatcher()).priceCalculator()).pricePerMint();
    }

    // Override transfer behavior based on value set for transferable flag
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override(IERC721, ERC721) {
        require(collectibleDetails[tokenId].transferable, "Collectible is not transferable");
        safeTransferFrom(from, to, tokenId, "");
    }

    function isRetired(address _patron) public virtual view returns(bool) {
        return !collectibleDetails[tokenOfOwnerByIndex(_patron, 0)].isActive;
    }

    /**
     * @notice Returns collectible details for an nft tokenID
     * @param _nftId uint256 NFT ID for which details need to be fetched
    */
    function getNFTDetails(uint256 _nftId) public virtual view returns(CollectibleDetails memory) {
        return collectibleDetails[_nftId];
    }

    function _setRedemption(uint256 _collectibleId) internal virtual {
        collectibleDetails[_collectibleId].redeemed = true;
    }

    function dataURI() public virtual view returns(string memory) {
        return collectibleData.dataURI;
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        ERC721Enumerable._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        ERC721URIStorage._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        _requireMinted(tokenId);
        return collectibleData.dataURI;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return ERC721Enumerable.supportsInterface(interfaceId);
    }

    function ownerOf(uint256 tokenId)
        public
        view
        override(ICollectible, IERC721, ERC721)
        returns (address)
    {
        return ERC721.ownerOf(tokenId);
    }

    function _msgSender() internal view virtual override(Context, DAOAccessControlled) returns (address sender) {
        return DAOAccessControlled._msgSender();
    }

    function _msgData() internal view virtual override(Context, DAOAccessControlled) returns (bytes calldata) {
        return DAOAccessControlled._msgData();
    }

    /**
     * @notice get the collectible location
     * @return (points, radius) (string[], uint256) Location details
    */
    function getLocationDetails() public view returns(string[] memory, uint256){
        return (collectibleData.area.points, collectibleData.area.radius);
    }

    function getLinkedCollectibles() external view override returns(address[] memory) {
        return linkedCollectibles;
    }

    /**
     * @notice Used to send the NFT to another blockchain
     * @param _destinationChainId uint16 Chain ID for destination chain
     * @param _collectibleId uint256 Collectible ID for the NFT to be transferred
    */
    function sendCollectibleToChain(uint16 _destinationChainId, uint256 _collectibleId) external payable {
        
        require(_msgSender() == ownerOf(_collectibleId), 'SENDER NOT OWNER OF THE TOKEN');
        
        // Burn the NFT on this chain so it can be reinstantiated on the destination chain
        _burn(_collectibleId);

        // Prepare payload to mint NFT and restore state on destination chain
        bytes memory payload = abi.encode(msg.sender, _collectibleId, collectibleDetails[_collectibleId]);

        // Encode the adapterParams to require more gas for the destination function call (and LayerZero message fees)
        // You can see an example of this here: https://layerzero.gitbook.io/docs/guides/advanced/relayer-adapter-parameters
        uint16 version = 1;
        uint256 gas = 200000;
        bytes memory adapterParams = abi.encodePacked(version, gas);
        (uint256 messageFee, ) = this.estimateFees(
            _destinationChainId,
            address(this),
            payload,
            false,
            adapterParams
        );

        // Send the message to the LayerZero endpoint to initiate the NFT transfer
        require(msg.value >= messageFee, 'NOT ENOUGH VALUE TO PAY FOR GAS');

        _lzSend(_destinationChainId, payload, payable(msg.sender), address(0x0), adapterParams, msg.value);

        // Emit an event for transfer of NFT to another chain
        emit SentNFT(_msgSender(), _destinationChainId, _collectibleId);

    }

    /**
     * @notice Receives the message from the endpoint on the destination chain to mint/remint the NFT on this chain
     * @param _srcChainId uint16 Chain ID for source chain
     * @param _from uint256 address of the sender
     * @param _nonce uint64 Nonce
     * @param _payload bytes Data needed to restore the state of the NFT on this chain
    */
    function _nonblockingLzReceive(uint16 _srcChainId, bytes memory _from, uint64 _nonce, bytes memory _payload) internal override {        
        address from;
        assembly {
            from := mload(add(_from, 20))
        }

        (address toAddress, uint256 collectibleId, CollectibleDetails memory srcCollectibleDetails) = abi.decode(
            _payload,
            (address, uint256, CollectibleDetails)
        );

        // Mint the NFT on this chain
        _safeMint(toAddress, collectibleId);

        collectibleDetails[collectibleId] = srcCollectibleDetails;

        // Emit an event for reception of NFT on destination chain
        emit ReceivedNFT(toAddress, _srcChainId, collectibleId);
    }
    
    /**
     * @notice Returns an estimate of cross chain fees for the message to the remote endpoint when doing an NFT transfer
     * @param _dstChainId uint16 Chain ID for destination chain
     * @param _userApplication uint256 address of the sender UA
     * @param _payload uint64 Data needed to restore the state of the NFT on this chain 
     * @param _payInZRO bytes 
     * @param _adapterParams bytes
    */
    function estimateFees(uint16 _dstChainId, address _userApplication, bytes calldata _payload, bool _payInZRO, bytes calldata _adapterParams) external view returns (uint256 nativeFee, uint256 zroFee) {
        return
            ILayerZeroEndpoint(lzEndpoint).estimateFees(
                _dstChainId,
                _userApplication,
                _payload,
                _payInZRO,
                _adapterParams
            );
    }
}
