// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Context.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./IERC721.sol";
import "./SafeMath.sol";
import "./PalToken.sol";
import "./IGenesisOwnership.sol";

contract PalMinter is Ownable, Pausable {
    using SafeMath for uint256;
    IGenesisOwnership public genesisOwnership;
    PalToken public palToken;
    address public treasury;
    address public daoWallet;
    uint256[] private rarityCooldownTimes;
    uint256[] private rarityPrices;
    uint256 private treasuryPercentage;

    mapping(uint256 => uint256) private genesisCooldownEnd;
    mapping(uint256 => uint256[]) private genesisToPals;

    event PalMinted(uint256 indexed genesisTokenId, uint256 indexed palTokenId, PalToken.Rarity rarity);
    event MintingPriceUpdated(PalToken.Rarity rarity, uint256 previousPrice, uint256 newPrice);
    event CooldownTimeUpdated(PalToken.Rarity rarity, uint256 previousTime, uint256 newTime);
    event TreasuryUpdated(address previousTreasury, address newTreasury);
    event DAOWalletUpdated(address previousTreasury, address newDAOWallet);
    event TreasuryPercentageUpdated(uint256 previousTreasuryPercentage, uint256 newTreasuryPercentage);

    constructor(address _genesisOwnership, address _palToken, address _treasury, address _daoWallet, uint256 _treasuryPercentage) {
        genesisOwnership = IGenesisOwnership(_genesisOwnership);
        palToken = PalToken(_palToken);
        treasury = _treasury;
        daoWallet = _daoWallet;
        treasuryPercentage = _treasuryPercentage;
        rarityCooldownTimes = [4 hours, 72 hours, 120 hours, 168 hours, 999999 hours, 999999 hours];
        rarityPrices = [0.002 ether, 0.01 ether, 0.1 ether, 0.5 ether, 999999 ether, 999999 ether];
    }

    function mintPal(uint256 _genesis, PalToken.Rarity _rarity) external payable whenNotPaused {
        require(genesisOwnership.ownerOf(_genesis) == _msgSender(), "PalMinter: Must be an owner of the Genesis to mint a Pal");
        require(msg.value == getMintingPrice(_rarity), "PalMinter: Invalid payment amount");
        require(isPalMintable(_genesis), "PalMinter: Cannot mint Pal yet");

        uint256 treasuryAmount = (msg.value.mul(getTreasuryPercentage())).div(10000);
        uint256 daoWalletAmount = msg.value.sub(treasuryAmount);
        payable(treasury).transfer(treasuryAmount);
        payable(daoWallet).transfer(daoWalletAmount);

        genesisCooldownEnd[_genesis] = block.timestamp + getCooldownTime(_rarity);
        palToken.mint(_msgSender(), _rarity);
        uint256 newPalTokenId = palToken.tokenByIndex(palToken.totalSupply() - 1);
        genesisToPals[_genesis].push(newPalTokenId);
        emit PalMinted(_genesis, newPalTokenId, _rarity);
    }

    function getMintingPrice(PalToken.Rarity _rarity) public view returns (uint256) {
        return rarityPrices[uint256(_rarity)];
    }

    function getCooldownTime(PalToken.Rarity _rarity) public view returns (uint256) {
        return rarityCooldownTimes[uint256(_rarity)];
    }

    function getPalsMintedByGenesis(uint256 _genesis) external view returns (uint256[] memory) {
        return genesisToPals[_genesis];
    }

    function getGenesisCooldownEnd(uint256 _genesis) public view returns (uint256) {
        return genesisCooldownEnd[_genesis];
    }

    function isPalMintable(uint256 _genesis) public view returns (bool) {
        return genesisCooldownEnd[_genesis] <= block.timestamp;
    }

    function updateMintingPrice(PalToken.Rarity _rarity, uint256 _price) external onlyOwner {
        uint256 oldPrice = rarityPrices[uint256(_rarity)];
        rarityPrices[uint256(_rarity)] = _price;
        emit MintingPriceUpdated(_rarity, oldPrice, _price);
    }

    function updateCooldownTime(PalToken.Rarity _rarity, uint256 _cooldownTime) external onlyOwner {
        uint256 oldCooldownTime = rarityCooldownTimes[uint256(_rarity)];
        rarityCooldownTimes[uint256(_rarity)] = _cooldownTime;
        emit CooldownTimeUpdated(_rarity, oldCooldownTime, _cooldownTime);
    }

    function setTreasury(address _treasury) external onlyOwner {
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    function setDAOWallet(address _daoWallet) external onlyOwner {
        address oldDAOWallet = daoWallet;
        daoWallet = _daoWallet;
        emit DAOWalletUpdated(oldDAOWallet, _daoWallet);
    }

    function setTreasuryPercentage(uint256 _treasuryPercentage) external onlyOwner {
        require(_treasuryPercentage <= 10000, "PalMinter: Invalid treasury percentage");
        uint256 oldTreasuryPercentage = treasuryPercentage;
        treasuryPercentage = _treasuryPercentage;
        emit TreasuryPercentageUpdated(oldTreasuryPercentage, _treasuryPercentage);
    }

    function getTreasuryPercentage() public view returns (uint256) {
        return treasuryPercentage;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
