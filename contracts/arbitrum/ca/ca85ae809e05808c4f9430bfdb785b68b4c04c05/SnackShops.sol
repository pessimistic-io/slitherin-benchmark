// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721Upgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./ERC2981Upgradeable.sol";
import "./MerkleProofUpgradeable.sol";
import "./LockRegistryUpgradeable.sol";
import "./SnackFounders.sol";

/// @title Smol Snack Shops (UUPS Upgradeable ERC721) 
/// @author Gearhart
/// @notice Includes non-escrow staking. 
/// @dev Credit to OwlOfMoistness for Lock Registry inspiration.

contract SmolSnackShops is Initializable, ERC721Upgradeable, AccessControlUpgradeable, UUPSUpgradeable, ERC2981Upgradeable, LockRegistryUpgradeable {
    
    using StringsUpgradeable for uint256;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter private _tokenIdCounter;
    
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public merkleRoot;

    string public baseURI;
    string public suffixURI;
    
    uint256 public maxSupply;
    uint256 public saleNumber;
    uint256 public shopSalePrice;
    uint256 public discountShopSalePrice;
    
    bool public preSaleStatus;
    bool public publicSaleStatus;

    address public teamWallet;
    address public foundersTokenAddress;
    SnackShopFounders ssf;
    
    mapping(address => mapping(uint => bool)) public whitelistClaimedPerSale;
    mapping(uint256 => uint256) public shopIdToReferalCode;

    /** 
     * @dev Lock registry interface
	 *     bytes4(keccak256('freeId(uint256,address)')) == 0x94d216d6
	 *     bytes4(keccak256('isUnlocked(uint256)')) == 0x72abc8b7
	 *     bytes4(keccak256('lockCount(uint256)')) == 0x650b00f6
	 *     bytes4(keccak256('lockId(uint256)')) == 0x2799cde0
	 *     bytes4(keccak256('lockMap(uint256,uint256)')) == 0x2cba8123
	 *     bytes4(keccak256('lockMapIndex(uint256,address)')) == 0x09308e5d
	 *     bytes4(keccak256('unlockId(uint256)')) == 0x40a9c8df
	 *     bytes4(keccak256('approvedContract(address)')) == 0xb1a6505f
     * 
	 *     => 0x94d216d6 ^ 0x72abc8b7 ^ 0x650b00f6 ^ 0x2799cde0 ^
	 *        0x2cba8123 ^ 0x09308e5d ^ 0x40a9c8df ^ 0xb1a6505f == 0x706e8489
	 */
	bytes4 private constant _INTERFACE_TOKENID_ERC721X = 0x706e8489;


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    function initialize() initializer public {
        __ERC721_init("Smol Snack Shop", "SNACK");
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ERC2981_init();
        __LockRegistryUpgradeable_init();


        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        teamWallet = 0xA220eDAC4ab66a955C1117e962dd139eB020314C;
        _setDefaultRoyalty(teamWallet, 750);
        merkleRoot = 0xd4453790033a2bd762f526409b7f358023773723d9e9bc42487e4996869162b6;
        maxSupply = 500;
        shopSalePrice = 0.03 ether;
        discountShopSalePrice = 0.03 ether;        
    }


// Mint Functions & Checks

    /// @notice Mints shops during presale and valadates merkle proof to check WL status.
    /// @param referalCode Minters choice of referal code. Links their shop to founders token for royalty calculations. 
    /// @param proof Merkle Proof for msg.sender to be compared against the stored Merkle root for WL verification.
    function preSaleMint (uint256 referalCode, bytes32[] calldata proof) external payable {
        if (!preSaleStatus) revert PreSaleNotActive();
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        if (!MerkleProofUpgradeable.verify(proof, merkleRoot, leaf)) revert InvalidMerkleProof();
        if (whitelistClaimedPerSale[msg.sender][saleNumber]) revert PreSaleAllocationExceeded();
        _priceCheck(referalCode);
        whitelistClaimedPerSale[msg.sender][saleNumber] = true;
        _mintShop(msg.sender, referalCode);
    }

    /// @notice Mints shops during public sale. 
    /// @param referalCode Minters choice of referal code. Links their shop to founders token for royalty calculations.
    function publicMint (uint256 referalCode) external payable {
        if (!publicSaleStatus) revert PublicSaleNotActive();
        _priceCheck(referalCode);
        _mintShop(msg.sender, referalCode);
    }

    /// @dev Internal mint function to limit repeated code.
    function _mintShop (address _to, uint256 _referalCode) internal {
        if (_tokenIdCounter.current() + 1 > maxSupply) revert MaxSupplyExceeded();
        _tokenIdCounter.increment();
        uint256 shopId = _tokenIdCounter.current();
        if (_referalCode > 0) {
            shopIdToReferalCode[shopId] = _referalCode;
        }
        _mint(_to, shopId);
    }

    /// @dev Internal function checks if referal code is valid or not by calling founders token contract.
    /// @param _referalCode Referal code used must be assigned to a minted founders token to get the discounted price.
    function _priceCheck(uint256 _referalCode) internal view {
        if (msg.sender != tx.origin) revert NonEOA();
        if (_referalCode == 0){    
            if (msg.value != shopSalePrice) revert InvalidEtherAmount(msg.value, shopSalePrice);
        }
        else {
            if (ssf.referalCodeToFoundersId(_referalCode) == 0) revert InvalidReferalCode();
            if (msg.value != discountShopSalePrice) revert InvalidEtherAmount(msg.value, discountShopSalePrice);
        }
    }

    /// @notice Mints and sends shop tokens free of charge. Arrays must be same length. Only callable from OPERATOR_ROLE.
    /// @dev Double check referalCodes in the input array because team mint does not check if they are valid like public and pre-sale do.
    /// @param to Array of addresses to recieve shop tokens.
    /// @param referalCode Array of referal codes to attach each shop to the founders token that referred them.
    function teamMint(address [] calldata to, uint256 [] calldata referalCode) external onlyRole(OPERATOR_ROLE){
        if (to.length != referalCode.length) revert ArrayLengthMismatch();
        if (_tokenIdCounter.current() + to.length > maxSupply) revert MaxSupplyExceeded();
        for (uint i=0; i < to.length; i++) {
            _mintShop(to[i], referalCode[i]);
        }
    }


// Staking Functionality (Lock Registry)

    /// @notice Override to prevent transfer of locked tokens.
    function transferFrom(address from, address to, uint256 tokenId) public override virtual {
		if (!isUnlocked(tokenId)) revert TokenIsLocked();
		ERC721Upgradeable.transferFrom(from, to, tokenId);
	}

    /// @notice Override to prevent safeTransfer of locked tokens.
	function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override virtual {
		if (!isUnlocked(tokenId)) revert TokenIsLocked();
		ERC721Upgradeable.safeTransferFrom(from, to, tokenId, data);
	}

    /// @notice Stake shop token to make NFT available in game.
    /// @dev Adds a lock to token id to prevent transfer while playing. Changes msg.sender to this address to pass approvedContract staking check. 
    /// @param tokenId Token Id to be staked by owner.
    function insertGameCartridge(uint256 tokenId) external {
        if (ownerOf(tokenId) != msg.sender) revert MustBeTokenOwnerToLock(); 
        this.lockId(tokenId);
    }

    /// @notice Unstake shop token to remove NFT from game.
    /// @dev Removes a lock from token id to allow transfer after playing. Changes msg.sender to this address to pass approvedContract staking check. 
    /// @param tokenId Token Id to be unstaked by owner.
    function removeGameCartridge(uint256 tokenId) external {
        if (ownerOf(tokenId) != msg.sender) revert MustBeTokenOwnerToUnlock();
        this.unlockId(tokenId);
    }

	/// @notice Increments lockCount for a specific token ID on behalf of owner making it untransferable until all locks are removed. Only callable from approved contract addresses.
    /// @param tokenId Token Id to be locked.
    function lockId(uint256 tokenId) external override virtual {
		if (!_exists(tokenId)) revert TokenIdDoesNotExist();
		_lockId(tokenId);
	}

	/// @notice Decrements lockCount for a specific token ID on behalf of owner making it transferable again if lockCount for that token is 0. Only callable from approved contract addresses.
    /// @param tokenId Token Id to be unlocked.
    function unlockId(uint256 tokenId) external override virtual {
		if (!_exists(tokenId)) revert TokenIdDoesNotExist();
		_unlockId(tokenId);
	}

	/// @notice Decrements lockCount for a specific token ID but ONLY if that locking contract has been revoked from approvedContracts.
    /// @dev Must first be sure contractAddress has been revoked. The mapping "approvedContract[contractAddress]" must be false.
    /// @param tokenId Token Id to be freed.
    /// @param contractAddress A contract that locked the token id BUT is no longer approved under approvedContracts.
    function freeId(uint256 tokenId, address contractAddress) external override virtual {
		if (!_exists(tokenId)) revert TokenIdDoesNotExist();
		_freeId(tokenId, contractAddress);
	}

    /// @notice Give contract addresses approval to lock or unlock tokens at the holders request. Only callable from OPERATOR_ROLE.
    /// @param contractAddresses Array of contract addresses that will have their approvals updated.
    /// @param approvals True or false. Either approve or revoke contract in contractAddresses[] at the same index as approvals[].
    function updateApprovedContracts(address[] calldata contractAddresses, bool[] calldata approvals) external onlyRole(OPERATOR_ROLE) {
        if (contractAddresses.length != approvals.length) revert ArrayLengthMismatch();
		for (uint256 i = 0; i < contractAddresses.length; i++) {
		    approvedContract[contractAddresses[i]] = approvals[i];
        }
    } 


// Setter, withdraw, and View Functions
    
    /// @notice Set new base URI to be concatenated with token Id + suffix. Only callable from OPERATOR_ROLE.
    /// @param newBaseURI Portion of URI to come before token Id + Suffix. 
    function setBaseURI(string calldata newBaseURI) external onlyRole(OPERATOR_ROLE){
        baseURI = newBaseURI;
    }

    /// @notice Set new URI suffix to be added to the end of baseURI + token Id. Only callable from OPERATOR_ROLE.
    /// @param newSuffixURI Example suffix: ".json" for IPFS files
    function setSuffixURI(string calldata newSuffixURI) external onlyRole(OPERATOR_ROLE){
        suffixURI = newSuffixURI;
    }

    /// @notice Change MerkleRoot used for WL verification. Only callable from OPERATOR_ROLE.
    /// @param newRoot Merkle root derived from new Merkle tree to update whitelisted addresses.
    function setMerkleRoot(bytes32 newRoot) external onlyRole(OPERATOR_ROLE) {
        merkleRoot = newRoot;
    }
    
    /// @notice Turn public sale on/off. Only callable from OPERATOR_ROLE.
    /// @param status True for on False for off. 
    function setPublicSaleStatus(bool status) external onlyRole(OPERATOR_ROLE) {
        publicSaleStatus = status;
    }

    /// @notice Turn presale on/off. Only callable from OPERATOR_ROLE.
    /// @param status True for on False for off. 
    function setPreSaleStatus(bool status) external onlyRole(OPERATOR_ROLE) {
        preSaleStatus = status;
    }

    /// @notice Change the shop mint price. Only callable from OPERATOR_ROLE.
    /// @param newPriceInEth New price per shop denominated in ETH. 
    function setShopSalePrice(uint256 newPriceInEth) external onlyRole(OPERATOR_ROLE) {
        shopSalePrice = newPriceInEth;
    }

    /// @notice Change the discounted shop mint price. Only callable from OPERATOR_ROLE.
    /// @param newPriceInEth New discounted price per shop denominated in ETH. 
    function setDiscountShopSalePrice(uint256 newPriceInEth) external onlyRole(OPERATOR_ROLE) {
        discountShopSalePrice = newPriceInEth;
    }

    /// @notice Change the founders token contract address. Only callable from OPERATOR_ROLE.
    /// @param newFoundersAddress New contract address to check if referal codes are valid during discount mint. 
    function setFoundersTokenAddress(address newFoundersAddress) external onlyRole(OPERATOR_ROLE) {
        if (newFoundersAddress == address(0)) revert InvalidAddress();
        foundersTokenAddress = newFoundersAddress;
        ssf = SnackShopFounders(newFoundersAddress);
    }

    /// @notice Change the max supply of shop NFTs. Only callable from OPERATOR_ROLE.
    /// @param newMaxSupply New maximum amount of shops that can be minted. Must be larger than current supply. 
    function setMaxSupply(uint256 newMaxSupply) external onlyRole(OPERATOR_ROLE) {
        if (newMaxSupply < _tokenIdCounter.current()) revert InvalidMaxSupply();
        if (publicSaleStatus || preSaleStatus) revert DisableSaleToChangeSupply();
        maxSupply = newMaxSupply;
    }
    
    /// @notice Set royalty reciever address and numerator used in royalty fee calculation. Only callable from OPERATOR_ROLE.
    /// @param newRoyaltyReciever Address that will recieve royalty payouts.
    /// @param royaltyFeeNumerator Numerator to be divided by 10000 for royalty fee calculations.
    function setDefaultRoyalty(address newRoyaltyReciever, uint96 royaltyFeeNumerator) external onlyRole(OPERATOR_ROLE) {
        _setDefaultRoyalty(newRoyaltyReciever, royaltyFeeNumerator);
    }

    /// @notice Remove default royalty reciever address and numerator used in fee calculaion. Only callable from OPERATOR_ROLE.
    function removeRoyaltyInfo() external onlyRole(OPERATOR_ROLE) {
        _deleteDefaultRoyalty();
    }

    /// @notice Increase sale number to reset WL mint allowance. Only callable from OPERATOR_ROLE.
    /// @dev Increments sale number which effectivly resets whitelistClaimed mapping for next sale.
    function incrementSaleNumber() external onlyRole(OPERATOR_ROLE) {
        saleNumber ++;
    }

    /// @notice Change the team wallet address. Only callable from DEFAULT_ADMIN_ROLE.
    /// @param newTeamWallet New team wallet address for withdrawls. 
    function setTeamWalletAddress(address newTeamWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTeamWallet == address(0)) revert InvalidAddress();
        teamWallet = newTeamWallet;
    }
    
    /// @notice Withdraw all Ether from contract. Only callable from DEFAULT_ADMIN_ROLE.
    function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool success, ) = teamWallet.call{value: address(this).balance}('');
        if (!success) revert WithdrawFailed();
    }

    /// @dev If removed, contract will no longer be upgradable. Only callable from DEFAULT_ADMIN_ROLE.
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(DEFAULT_ADMIN_ROLE)
        override
    {}

    /// @notice Get minted token supply.
    function currentSupply() external view returns(uint256) {
        return _tokenIdCounter.current();
    }

    /// @dev override of parent contract to return base URI to be concatenated with token ID + suffix.
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /// @dev override of parent contract that returns base URI concatenated with token ID + suffix. 
    ///@param tokenId Token id used to fetch full URI.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert TokenIdDoesNotExist();
        string memory URI = _baseURI();
        return bytes(URI).length > 0 ? string(abi.encodePacked(URI, tokenId.toString(), suffixURI)) : "";
    } 

    /// @dev The following functions are overrides required by Solidity. Also added interface support for lockRegistry.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, AccessControlUpgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return interfaceId == _INTERFACE_TOKENID_ERC721X || super.supportsInterface(interfaceId);
    } 
}
