// SPDX-License-Identifier: MIT
/// @author MrD 

pragma solidity >=0.8.11;

import "./Ownable.sol";
import "./AccessControlEnumerable.sol";
import "./ReentrancyGuard.sol";
import "./IERC1155Receiver.sol";
import "./IERC20.sol";

import "./ERC1155Tradable.sol";
import "./INftPacks.sol";
import "./INftRewards.sol";
import "./IGameCoordinator.sol";
import "./IVault.sol";
import "./IERC20Minter.sol";

contract NftStore is Ownable, IERC1155Receiver, ReentrancyGuard, AccessControlEnumerable {

    ERC1155Tradable private nft;
    INftPacks private nftPacks;
    IGameCoordinator private gameCoordinator;

    INftRewards private nftRewardsContract;
    IERC20Minter private primaryToken;

    bytes32 public constant TEAM_ROLE = keccak256("TEAM_ROLE");
    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");

    address payable private operationsWallet;
    address payable private devWallet;
    address public constant burnAddress = address(0xdead);
    bool public storeActive;

    IVault public vault;
    uint256 public vaultPercent;
    address payable public vaultTvl;

    uint256 public totalPurchasedAmount;
    uint256 public totalBurnAmount;
    uint256 public totalNftsRedeemed;
    uint256 public totalPacksRedeemed;
    mapping(address => uint256) public totalExtraPurchasedAmount;


    uint256 public tokenPriceMod = 1 ether;
    uint256 public nativePriceMod = 1 ether;

    // required seconds between purchases
    uint256 public purchaseCoolDown;

    struct ItemInfo {
        uint256 id; //pack/nft id
        bool isActive; // flag to check if the item is still active
        bool useWhitelist; // if true only addresses whitelisted for this item can redeem
        uint256 nativePrice; // cost in Native Token/ETH etc.
        uint256 burnCost; // primary token burn cost
        IERC20 extraToken; // erc20/bep20 token address, can be set by itself or with the
        uint256 extraPrice; // the amount of the erc20 passed in to charge
        uint256 maxRedeem;  // max that can be redeemed
        uint256 totalRedeemed;// total redeemed 
        uint256 maxPerAddress; //max one address can get
        uint256 tierLimit; //limit to only this tier and above
        uint256 levelLimit; //limit to only this game level and above

        
    }


    mapping(address => uint256) public totalUserNfts;
    mapping(address => uint256) public totalUserPacks;
    mapping(address => uint256) public lastPurchase;

    // keep track of nfts and packs per address
    mapping(address => mapping(uint256 => uint256)) public userTotalByNft;
    mapping(address => mapping(uint256 => uint256)) public userTotalByPack;
    
    mapping(uint256 => ItemInfo) public nfts;
    mapping(uint256 => ItemInfo) public packs;
    mapping(uint256 => mapping(address => bool)) private packsWhitelist;
    mapping(uint256 => mapping(address => bool)) private nftsWhitelist;
    
    mapping(uint256 => mapping(address => bool)) private packVoucher;
    mapping(uint256 => mapping(address => bool)) private nftVoucher;
    

    event NftSet(uint256 nftId,  uint256 amountNative, uint256 amountBurn, uint256 maxRedeem, uint256 maxPerAddress, uint256 tierLimit, uint256 levelLimit, address extraToken, uint256 extraPrice);
    event PackSet(uint256 packId, uint256 amountNative, uint256 amountBurn, uint256 maxRedeem, uint256 maxPerAddress, uint256 tierLimit, uint256 levelLimit, bool useWhitelist, address extraToken, uint256 extraPrice);
    event NftRedeemed(address indexed user, uint256 nftId, uint256 amount, uint256 burn, uint256 extraPrice, bool hasVoucher, uint256 toVault, uint256 toDev);
    event PackRedeemed(address indexed user, uint256 packId, uint256 amount, uint256 burn, uint256 extraPrice, bool hasVoucher, uint256 toVault, uint256 toDev);
    event NftVoucherSet(address indexed user, address indexed sender, uint256 nftId, bool hasVoucher);
    event PackVoucherSet(address indexed user, address indexed sender, uint256 packId, bool hasVoucher);
    event NftSetActive(uint256 nftId, bool isActive);
    event PackSetActive(uint256 packId, bool isActive);
    event TokenPriceModSet(uint256 priceMod);
    event NativePriceModSet(uint256 priceMod);
    event StoreSetActive(bool isActive);
    event PurchaseCoolDownSet(uint256 purchaseCoolDown);

    event SetNftPackContract(address indexed user, INftPacks contractAddress);
    event SetGameCoordinatorContract(address indexed user, IGameCoordinator contractAddress);
    event SetTheNftRewardsContract(address indexed user, INftRewards contractAddress);
    event SetOperationsWallet(address indexed user, address operationsWallet);
    event SetDevWallet(address indexed user, address devWallet);

    constructor(
        ERC1155Tradable _nftAddress, 
        INftPacks _nftPacksAddress, 
        IGameCoordinator _gameCoordinator, 
        IERC20Minter _tokenAddress,
        address payable _operationsWallet, 
        address payable _devWallet, 
        INftRewards _nftRewardsContract,
        IVault _vault,
        address payable _vaultTvl,
        uint256 _vaultPercent
    ) {
        require(_operationsWallet != address(0), 'bad address');
        require(_devWallet != address(0), 'bad address');

        nft = _nftAddress;
        nftPacks = _nftPacksAddress;
        gameCoordinator = _gameCoordinator;
        primaryToken = _tokenAddress;
        nftRewardsContract = _nftRewardsContract;
        operationsWallet = _operationsWallet;
        devWallet = _devWallet;
        vault = _vault;
        vaultPercent = _vaultPercent;
        vaultTvl = _vaultTvl;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // modifier for functions only the team can call
    modifier onlyTeam() {
        require(hasRole(TEAM_ROLE,  msg.sender) || msg.sender == owner(), "Caller not in Team");
        _;
    }

    // modifier for limiting what addresses can whitelist packs and nfts
    modifier onlyWl() {
        require(hasRole(TEAM_ROLE,  msg.sender) || hasRole(WHITELIST_ROLE,  msg.sender) || msg.sender == owner(), "Caller not in Wl address");
        _;
    }

    function redeemNft(uint256 _nftId) public payable nonReentrant {
        
        bool burnSuccess = false;
        require(storeActive && nfts[_nftId].isActive && nfts[_nftId].id != 0, "Nft not found");
        require(purchaseCoolDown == 0 || block.timestamp >= lastPurchase[msg.sender] + purchaseCoolDown, "Purchase Cooldown Active");

        uint256 burnCost = (nfts[_nftId].burnCost * tokenPriceMod)/1 ether;
        uint256 nativeCost = (nfts[_nftId].nativePrice * nativePriceMod)/1 ether;
        uint256 extraPrice = nfts[_nftId].extraPrice;
        uint256 toVault = 0;
        uint256 toDev = 0;

        uint256 userTier;
        if(address(nftRewardsContract) != address(0)) {
            userTier = nftRewardsContract.getUserTier(msg.sender);
        }

        uint256 userLevel;
        if(address(gameCoordinator) != address(0)) {
            userLevel = gameCoordinator.getLevel(msg.sender);
        }

        require(( nfts[_nftId].maxRedeem == 0 || nfts[_nftId].totalRedeemed < nfts[_nftId].maxRedeem) && ( nfts[_nftId].maxPerAddress == 0 || userTotalByNft[msg.sender][_nftId] < nfts[_nftId].maxPerAddress), "Max nfts Redeemed");
        require(userTier >= nfts[_nftId].tierLimit, "Tier too low");
        require(userLevel >= nfts[_nftId].levelLimit, "Game Level too low");

        require(nftVoucher[_nftId][msg.sender] || msg.value >=  nfts[_nftId].nativePrice, "Not enough Native Token to redeem for nft");
        require(nftVoucher[_nftId][msg.sender] || primaryToken.balanceOf(msg.sender) >=  burnCost, "Not enough primary tokens to burn to redeem nft");
        require(nftVoucher[_nftId][msg.sender] || extraPrice == 0 || nfts[_nftId].extraToken.balanceOf(msg.sender) >=  extraPrice, "Not enough secondary token to spend for nft");

        require(nft.balanceOf(address(this),_nftId) > 0, "Out of Stock"); 

        bool hasVoucher;
        // using a voucher
        if(nftVoucher[_nftId][msg.sender]){
            hasVoucher = true;
            burnCost = 0;
            nativeCost = 0;
            extraPrice = 0;
        } else {
             // if we are taking Native Token transfer it
            if(nfts[_nftId].nativePrice > 0){
                totalPurchasedAmount = totalPurchasedAmount + nativeCost;

                // send 20% to the vault
                toVault = (nativeCost * vaultPercent) / 100;
                (bool sent,) = payable(address(vaultTvl)).call{value: toVault}("");
                require(sent, "Failed to send");

                //20% of the remaining to dev
                toDev = (nativeCost - toVault)/5;
                devWallet.transfer(toDev);

                // the rest to the operations wallet
                operationsWallet.transfer(nativeCost - toVault - toDev);
            }

            // if we are taking a secondary Token transfer it
            if(nfts[_nftId].extraPrice > 0){
                totalExtraPurchasedAmount[address(nfts[_nftId].extraToken)] = totalExtraPurchasedAmount[address(nfts[_nftId].extraToken)] + nfts[_nftId].extraPrice;
                nfts[_nftId].extraToken.transferFrom(msg.sender, operationsWallet, nfts[_nftId].extraPrice);
                // bool extraSuccess = nfts[_nftId].extraToken.transferFrom(msg.sender, operationsWallet, nfts[_nftId].extraPrice);
                 // require(extraSuccess, "token: Send failed");
            }

            // if we need to burn burn it
            if(nfts[_nftId].burnCost > 0){
               
                 totalBurnAmount = totalBurnAmount + burnCost;
                 burnSuccess = primaryToken.transferFrom(msg.sender, burnAddress, burnCost);
                 require(burnSuccess, "primary tokens: Burn failed");
                 //give them shares
                 vault.giveAdjustTokenShares(msg.sender,burnCost);
                 // vault.giveShares(msg.sender, vault.adjustTokenShares(burnCost),false);
            }

        }

        // stats
        nfts[_nftId].totalRedeemed = nfts[_nftId].totalRedeemed + 1;
        totalNftsRedeemed = totalNftsRedeemed + 1;
        userTotalByNft[msg.sender][_nftId] = userTotalByNft[msg.sender][_nftId] + 1;
        totalUserNfts[msg.sender] = totalUserNfts[msg.sender] + 1;
        lastPurchase[msg.sender] = block.timestamp;


        // remove the voucher if one was used
        if(hasVoucher){
            nftVoucher[_nftId][msg.sender] = false;
        }

        // send the NFT
        nft.safeTransferFrom(address(this), msg.sender, _nftId, 1, "0x0");

        emit NftRedeemed(msg.sender, _nftId, nativeCost, burnCost, extraPrice, hasVoucher, toVault, toDev);
    }

    function redeemPack(uint256 _packId) public payable nonReentrant{
        bool burnSuccess = false;

        require(packs[_packId].id != 0, "Pack not found");
        require(storeActive && packs[_packId].isActive, "Pack Inactive");
        require(purchaseCoolDown == 0 || block.timestamp >= lastPurchase[msg.sender] + purchaseCoolDown, "Purchase Cooldown Active");
        require(!packs[_packId].useWhitelist || packsWhitelist[_packId][msg.sender], "Not on the Whitelist");

        uint256 burnCost =  (packs[_packId].burnCost * tokenPriceMod) / 1 ether;  
        uint256 nativeCost = (packs[_packId].nativePrice * nativePriceMod)/1 ether;
        uint256 extraPrice = packs[_packId].extraPrice;
        uint256 toVault = 0;
        uint256 toDev = 0;

        uint256 userTier;
        if(address(nftRewardsContract) != address(0)) {
            userTier = nftRewardsContract.getUserTier(msg.sender);
        }

        uint256 userLevel;
        if(address(gameCoordinator) != address(0)) {
            userLevel = gameCoordinator.getLevel(msg.sender);
        }

        require(
            ( packs[_packId].maxRedeem == 0 || packs[_packId].totalRedeemed < packs[_packId].maxRedeem) && 
            ( packs[_packId].maxPerAddress == 0 || userTotalByPack[msg.sender][_packId] < packs[_packId].maxPerAddress), 
        "Max packs Redeemed"
        );

        require(userTier >= packs[_packId].tierLimit, "Tier too low");
        require(userLevel >= packs[_packId].levelLimit, "Game Level too low");
        require(packVoucher[_packId][msg.sender] || msg.value >=  nativeCost, "Not enough Native Token to redeem pack");
        require(packVoucher[_packId][msg.sender] || primaryToken.balanceOf(msg.sender) >=  burnCost, "Not enough primary tokens to burn for pack");
        require(packVoucher[_packId][msg.sender] || extraPrice == 0 || packs[_packId].extraToken.balanceOf(msg.sender) >=  extraPrice, "Not enough seondairy tokens to spend for pack");

        bool hasVoucher;
        // using a voucher
        if(packVoucher[_packId][msg.sender]){
            hasVoucher = true;
            burnCost = 0;
            nativeCost = 0;
            extraPrice = 0;
        } else {
            // if we are taking Native Token transfer it
            if(packs[_packId].nativePrice > 0){
                totalPurchasedAmount = totalPurchasedAmount + nativeCost;
                
                // send 20% to the vault
                toVault = (nativeCost * vaultPercent) / 100;
                (bool sent, ) = payable(address(vaultTvl)).call{value: toVault}("");
                require(sent, "Failed to send");
                
                //20% of the remaining to dev
                toDev = (nativeCost - toVault)/5; 
                devWallet.transfer(toDev);

                // the rest to the operations wallet
                operationsWallet.transfer(nativeCost - toVault - toDev);

            }

            // if we are taking a secondary Token transfer it
            if(packs[_packId].extraPrice > 0){
                totalExtraPurchasedAmount[address(packs[_packId].extraToken)] = totalExtraPurchasedAmount[address(packs[_packId].extraToken)] + packs[_packId].extraPrice;
                
                packs[_packId].extraToken.transferFrom(msg.sender, operationsWallet, packs[_packId].extraPrice);
                // bool extraSuccess = packs[_packId].extraToken.transferFrom(msg.sender, operationsWallet, packs[_packId].extraPrice);
                //  require(extraSuccess, "token: Send failed");
            }

            // if we need to burn burn it
            if(packs[_packId].burnCost > 0){
               
                 totalBurnAmount = totalBurnAmount + burnCost;
                 burnSuccess = primaryToken.transferFrom(msg.sender, burnAddress, burnCost);
                 require(burnSuccess, "primary tokens: Burn failed");
                 vault.giveAdjustTokenShares(msg.sender,burnCost);
                 // vault.giveShares(msg.sender, vault.adjustTokenShares(burnCost),false);
            }
        }

        // stats
        packs[_packId].totalRedeemed = packs[_packId].totalRedeemed + 1;
        totalPacksRedeemed = totalPacksRedeemed + 1;
        userTotalByPack[msg.sender][_packId] = userTotalByPack[msg.sender][_packId] + 1;
        totalUserPacks[msg.sender] = totalUserPacks[msg.sender] + 1;
        lastPurchase[msg.sender] = block.timestamp;

        // remove the voucher if one was used
        if(hasVoucher){
            packVoucher[_packId][msg.sender] = false;
        }

        //send them the pack
         nftPacks.open(
          _packId,
          msg.sender,
          1
        );

        emit PackRedeemed(msg.sender, _packId, nativeCost, burnCost, extraPrice, hasVoucher, toVault, toDev);
    }

    function setPurchaseCoolDown(uint256 _purchaseCoolDown) public onlyTeam {
        purchaseCoolDown = _purchaseCoolDown;
        emit PurchaseCoolDownSet(_purchaseCoolDown);
    }

    /**
     * @dev Add or update a nft
     */
    function setNft(
        uint256 _nftId, 
        uint256 _amountNative, 
        uint256 _amountBurn, 
        IERC20 _extraToken,
        uint256 _extraPrice,
        uint256 _maxRedeem, 
        uint256 _maxPerAddress, 
        uint256 _tierLimit, 
        uint256 _levelLimit) public onlyOwner {
        nfts[_nftId].id = _nftId;
        nfts[_nftId].nativePrice = _amountNative;
        nfts[_nftId].burnCost = _amountBurn;
        nfts[_nftId].extraToken = _extraToken;
        nfts[_nftId].extraPrice = _extraPrice;
        nfts[_nftId].maxRedeem = _maxRedeem;
        nfts[_nftId].isActive = true;
        nfts[_nftId].maxPerAddress = _maxPerAddress;
        nfts[_nftId].tierLimit = _tierLimit;
        nfts[_nftId].levelLimit = _levelLimit;


        emit NftSet(_nftId, _amountNative, _amountBurn, _maxRedeem, _maxPerAddress, _tierLimit, _levelLimit, address(_extraToken), _extraPrice);
    }

    /**
     * @dev Add or update a pack
     */
    function setPack(
        uint256 _packId, 
        uint256 _amountNative, 
        uint256 _amountBurn, 
        IERC20 _extraToken,
        uint256 _extraPrice,
        uint256 _maxRedeem, 
        uint256 _maxPerAddress, 
        uint256 _tierLimit, 
        uint256 _levelLimit,
        bool _useWhitelist

    ) public onlyOwner {
        packs[_packId].id = _packId;
        packs[_packId].nativePrice = _amountNative;
        packs[_packId].burnCost = _amountBurn;
        packs[_packId].extraToken = _extraToken;
        packs[_packId].extraPrice = _extraPrice;
        packs[_packId].maxRedeem = _maxRedeem;
        packs[_packId].isActive = true;
        packs[_packId].maxPerAddress = _maxPerAddress;
        packs[_packId].tierLimit = _tierLimit;
        packs[_packId].levelLimit = _levelLimit;
        packs[_packId].useWhitelist = _useWhitelist;

        emit PackSet(_packId, _amountNative, _amountBurn, _maxRedeem, _maxPerAddress, _tierLimit, _levelLimit, _useWhitelist, address(_extraToken), _extraPrice);
    }


    function setNftActive(uint256 _nftId, bool _isActive) public onlyTeam {
        nfts[_nftId].isActive = _isActive;
        emit NftSetActive(_nftId, _isActive);
    }

    
    function setPackActive(uint256 _packId, bool _isActive) public onlyTeam {
        packs[_packId].isActive = _isActive;
        emit PackSetActive(_packId, _isActive);
    }


    function bulkAddNftWhitelist(uint256 _nftId, address[] calldata _wlAddresses) public onlyWl {
        for (uint256 i = 0; i < _wlAddresses.length; ++i) {
            _addNftWhitelist(_nftId, _wlAddresses[i]);
        }
    }

    function bulkRemoveNftWhitelist(uint256 _nftId, address[] calldata _wlAddresses) public onlyWl {
        for (uint256 i = 0; i < _wlAddresses.length; ++i) {
            _removeNftWhitelist(_nftId, _wlAddresses[i]);
        }
    }

    function addNftWhitelist(uint256 _nftId, address _user) public onlyWl {
        _addNftWhitelist(_nftId, _user);
    }

    function removeNftWhitelist(uint256 _nftId, address _user) public onlyWl {
        _removeNftWhitelist(_nftId, _user);
    }

    function isWhitelistedNft(uint256 _nftId, address _user) public view returns(bool) {
        return nftsWhitelist[_nftId][_user];
    }

    function _addNftWhitelist(uint256 _nftId, address _user) private {
        nftsWhitelist[_nftId][_user] = true;
    }

    function _removeNftWhitelist(uint256 _nftId, address _user) private {
        nftsWhitelist[_nftId][_user] = false;
    }


    function bulkAddPackWhitelist(uint256 _packId, address[] calldata _wlAddresses) public onlyWl {
        for (uint256 i = 0; i < _wlAddresses.length; ++i) {
            _addPackWhitelist(_packId, _wlAddresses[i]);
        }
    }

    function bulkRemovePackWhitelist(uint256 _packId, address[] calldata _wlAddresses) public onlyWl {
        for (uint256 i = 0; i < _wlAddresses.length; ++i) {
            _removePackWhitelist(_packId, _wlAddresses[i]);
        }
    }

    function addPackWhitelist(uint256 _packId, address _user)  public onlyWl {
        _addPackWhitelist(_packId, _user);
    }

    function removePackWhitelist(uint256 _packId, address _user) public onlyWl {
        _removePackWhitelist(_packId, _user);
    }

    function isWhitelisted(uint256 _packId, address _user) public view returns(bool) {
        return packsWhitelist[_packId][_user];
    }

    function _addPackWhitelist(uint256 _packId, address _user) private {
        packsWhitelist[_packId][_user] = true;
    }

    function _removePackWhitelist(uint256 _packId, address _user) private {
        packsWhitelist[_packId][_user] = false;
    }


    function hasNftVoucher(uint256 _nftId, address _user) public view returns(bool) {
        return nftVoucher[_nftId][_user];
    }

    function hasPackVoucher(uint256 _packId, address _user) public view returns(bool) {
        return packVoucher[_packId][_user];
    }


    function setNftVoucher(uint256 _nftId, address _user, bool _hasVoucher)  public onlyWl {
        nftVoucher[_nftId][_user] = _hasVoucher;
        emit NftVoucherSet(_user, msg.sender, _nftId, _hasVoucher);
    }


    function setPackVoucher(uint256 _packId, address _user, bool _hasVoucher)  public onlyWl {
        packVoucher[_packId][_user] = _hasVoucher;
        emit PackVoucherSet(_user, msg.sender, _packId, _hasVoucher);
    }

     /**
     * @dev Update the main token address only callable by the owner
     */
    function setPrimaryTokenContract(IERC20Minter _primaryToken) public onlyOwner {
        primaryToken = _primaryToken;
       // emit SetMnopTokenContract(msg.sender, _primaryToken);
    }

    /**
     * @dev Update the nft pack NFT contract address only callable by the owner
     */
    function setNftPacksContract(INftPacks _nftPacks) public onlyOwner {
        nftPacks = _nftPacks;
        emit SetNftPackContract(msg.sender, _nftPacks);
    }

    /**
     * @dev Update the Game Coordinator contract address only callable by the owner
     */
    function setGameCoordinatorContract(IGameCoordinator _gameCoordinator) public onlyOwner {
        gameCoordinator = _gameCoordinator;
        emit SetGameCoordinatorContract(msg.sender, _gameCoordinator);
    }

    /**
     * @dev Update the nft NFT contract address only callable by the owner
     */
   function setNftContract(ERC1155Tradable _nftAddress) public onlyOwner {
        nft = _nftAddress;
        // emit SetNftContract(msg.sender, _nftAddress);
    }

     /**
     * @dev Update the LP Staking contract address only callable by the owner
     */
    function setNftRewardsContract(INftRewards _nftRewardsContract) public onlyOwner {
        nftRewardsContract = _nftRewardsContract;
        emit SetTheNftRewardsContract(msg.sender, _nftRewardsContract);
    }

     /**
     * @dev Update operations wallet
     */
    function setOperationsWallet(address payable _operationsWallet) public onlyOwner {
        require(_operationsWallet != address(0), 'bad address');
        operationsWallet = _operationsWallet;
        emit SetOperationsWallet(msg.sender, _operationsWallet);
    }

    /**
     * @dev Update the dev wallet
     */
    function setDevWallet(address payable _devWallet) public onlyOwner {
        require(_devWallet != address(0), 'bad address');
        devWallet = _devWallet;
        emit SetDevWallet(msg.sender, _devWallet);
    }

    function setVault(IVault _vault, address payable _vaultTvl, uint256 _vaultPercent) public onlyOwner {
        vault = _vault;
        vaultTvl = _vaultTvl;
        vaultPercent = _vaultPercent;
    }

     /**
     * @dev Update the token price mod to scale all token prices
     */

    function setTokenPriceMod(uint256 _tokenPriceMod) public onlyTeam {
        tokenPriceMod = _tokenPriceMod;
        emit TokenPriceModSet(_tokenPriceMod);
    }

     /**
     * @dev Update the token price mod to scale all native prices
     */
    function setNativePriceMod(uint256 _nativePriceMod) public onlyTeam {
        nativePriceMod = _nativePriceMod;
        emit NativePriceModSet(_nativePriceMod);
    }

    /**
     * @dev Global flag to enable/disable the store
     */    
    function setStoreActive(bool _storeActive) public onlyTeam {
        storeActive = _storeActive;
        emit StoreSetActive(_storeActive);
    }


    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure override returns(bytes4) {
      return 0xf23a6e61;
    }


    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure override returns(bytes4) {
      return 0xbc197c81;
    }

    function supportsInterface(bytes4 interfaceID) public view virtual override(IERC165,AccessControlEnumerable) returns (bool) {
      return  interfaceID == 0x01ffc9a7 ||    // ERC-165 support (i.e. `bytes4(keccak256('supportsInterface(bytes4)'))`).
      interfaceID == 0x4e2312e0;      // ERC-1155 `ERC1155TokenReceiver` support (i.e. `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) ^ bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`).
  }
}
