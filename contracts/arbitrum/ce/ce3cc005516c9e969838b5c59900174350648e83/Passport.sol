// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Collectible.sol";
import "./IDispatcher.sol";
import "./IDAOAuthority.sol";

contract Passport is Collectible {
    
    using Counters for Counters.Counter;
    
    constructor(
        CollectibleData memory _collectibleData,
        Area memory _area,
        address _authority,
        address _loot8Token,
        address _layerzeroEndpoint
    ) Collectible(CollectibleType.PASSPORT, _collectibleData, _area, _authority, _loot8Token, _layerzeroEndpoint) {}

    /**
    * @notice Mints a passport NFT to the patron
    * @param _patron address Address of the patron
    * @param _expiry uint256 Expiration timestamp for the NFT
    * @param _transferable bool Flag to indicate if the NFT can be transferred to another wallet
    */
    function mint(
        address _patron,
        uint256 _expiry,
        bool _transferable
    ) external returns (uint256 _passportId)
    {
        address dispatcher = IDAOAuthority(authority).getAuthorities().dispatcher;

        require(msg.sender == dispatcher || isTrustedForwarder(msg.sender), 'UNAUTHORIZED');

        // Check if the patron already holds this passport
        require(balanceOf(_patron) == 0, "PATRON HOLDS PASSPORT");

        _passportId = Collectible._mint(_patron, _expiry, _transferable);

        IDispatcher(dispatcher).mintLinked(address(this), _patron, _expiry, _transferable);
    }

    function toggle(uint256 _passportId) external onlyEntityAdmin(collectibleData.entity) returns(bool _status) {
        _status = _toggle(_passportId);
    }

    function retire() external onlyEntityAdmin(collectibleData.entity) {
        _retire();
    }

    function creditRewards(address _patron, uint256 _amount) external onlyDispatcher {
        _creditRewards(_patron, _amount);
    }

    function debitRewards(address _patron, uint256 _amount) external onlyBartender(collectibleData.entity) {
        _debitRewards(_patron, _amount);
    }

    function linkCollectible(address _collectible) external onlyEntityAdmin(collectibleData.entity) {
        _linkCollectible(_collectible);
    }

    function delinkCollectible(address _collectible) external onlyEntityAdmin(collectibleData.entity) {
        _delinkCollectible(_collectible);
    }

    /**
     * @notice Returns Passport ID for a patron
    */
    function getPatronNFT(address _patron) public view returns(uint256) {
        return tokenOfOwnerByIndex(_patron, 0);
    }

    function updateDataURI(string memory _dataURI) external onlyEntityAdmin(collectibleData.entity) {
        _updateDataURI(_dataURI);
    }

    function setRedemption(uint256 _offerId) external onlyDispatcher {
        // Do nothing as business doesn't need this feature on passports
    }
}
