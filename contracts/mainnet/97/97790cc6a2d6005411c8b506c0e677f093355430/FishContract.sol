// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./ECDSA.sol";
import "./MerkleProof.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./ERC721A.sol";
import "./ERC721AQueryable.sol";
/**⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣤⣤⡀⠀⠀⠀⣠⣤⣤⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣴⣶⣿⣿⣿⣿⣿⡀⠀⢸⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣠⣶⡾⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⣧⠀⢸⣿⣿⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣶⣾⣿⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⢹⣿⣿⣿⣿⣶⡄⠙⣛⣁⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⡀⠀⠀⠀⠐⠿⢿⣿⣿⣿⣿⠁⠀⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⠈⢿⣿⣿⠿⢿⣷⣿⣿⣿⣶⡀⠀⠀⠀⢀⣠⣴⣶⣿⣿⣿⣆⠀⠀⠀⠀⢸⣿⣿⣿⣿⣶⣿⣿⣿⣷⣄⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⠀⠈⠉⠁⠀⠘⢿⣿⣿⣿⣿⡇⠀⠀⣶⣿⣿⣿⡿⣿⣿⣿⣿⣷⠄⠀⠀⢸⣿⣿⣿⣿⠿⣿⣿⣿⣿⣿⡆⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⣶⣶⣦⡄⠀⠀⠀⣿⣿⣿⣿⡇⠀⠀⣿⣿⣿⣿⡇⠹⣿⠿⠛⠁⠀⠀⠀⢸⣿⣿⣿⣿⠀⠘⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⠿⠿⠟⠁⠀⠀⠀⣿⣿⣿⣿⡇⠀⠀⣿⣿⣿⣿⣇⣠⣴⣾⣿⣦⡀⠀⠀⢸⣿⣿⣿⣿⠀⠀⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⣿⣿⣿⣿⡇⠀⠀⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣇⠀⠀⢸⣿⣿⣿⣿⠀⠀⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⣿⣿⣿⣿⡇⠀⠀⠈⠻⣟⣯⡉⠀⢹⣿⣿⣿⣿⠀⠀⢸⣿⣿⣿⣿⠀⠀⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⣿⣿⣿⣿⡇⠀⠀⣴⣿⣿⣿⣿⡄⢸⣿⣿⣿⣿⠀⠀⢸⣿⣿⣿⣿⡀⠀⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢀⣼⣿⣿⣿⣿⡆⠀⠀⠀⠀⠀⠀⣿⣿⣿⣿⣿⠄⠀⠙⣿⣿⣿⣿⣷⣾⣿⣿⠿⠋⠀⠀⢸⣿⣿⣿⣿⣷⠄⣿⣿⣿⣿⣿⠆⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⣼⣿⡿⠟⠋⠁⠀⠀⠀⠀⠀⠀⠀⠙⢿⡿⠟⠁⠀⠀⠀⠘⢿⣿⣿⠿⠛⠉⠀⠀⠀⠀⠀⠈⠻⣿⠿⠛⠁⠀⠈⠻⠟⠋⠁⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣦⡀⣀⣴⣦⡀⣀⣠⣶⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣤⣤⡀⣀⣴⣶⣄⠀⠀⠀⠀⠀⣀⣤⣤⡀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣤⣶⣿⣿⣿⣿⣧⣿⣿⣿⡟⠀⠀⣤⣶⣿⣿⣿⣿⣿⣆⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⡏⣿⣿⣿⡟⢹⣿⣿⣿⠀⠀⠀⠀⢀⣀⣀⣀⠀⠀⠀⣿⣿⣿⡟⠛⠛⠁⠈⣉⣉⡀⠀⠀⣿⣿⣿⡇⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⡇⣿⣿⣿⡇⢸⣿⣿⣿⠀⠀⠰⣾⣿⣿⣿⣿⣷⢀⣴⣿⣿⣿⣷⣶⠆⠀⢾⣿⣿⣿⠀⠀⣿⣿⣿⡇⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⡇⣿⣿⣿⡇⢸⣿⣿⣿⠀⠀⠀⠀⣀⣹⣿⣿⣿⡇⠀⣿⣿⣿⡏⠀⠀⠀⢸⣿⣿⣿⠀⠀⣿⣿⣿⣧⣿⣿⣿⣿⡄⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⡇⣿⣿⣿⡇⢸⣿⣿⣿⠀⣠⣶⣿⣿⢿⣿⣿⣿⡇⠀⣿⣿⣿⡇⠀⠀⠀⢸⣿⣿⣿⠀⠀⣿⣿⣿⡏⣿⣿⣿⣿⠁⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⡇⣿⣿⣿⡇⢸⣿⣿⣿⠀⣿⣿⣿⣿⢸⣿⣿⣿⡇⠀⣿⣿⣿⡇⠀⠀⠀⢸⣿⣿⣿⠀⠀⣿⣿⣿⡇⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⡇⣿⣿⣿⣧⣸⣿⣿⣿⣄⣿⣿⣿⣿⣼⣿⣿⣿⡇⠀⣿⣿⣿⣇⠀⠀⠀⢸⣿⣿⣿⠀⠀⣿⣿⣿⡇⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⢠⣾⣿⣿⠿⠋⠻⣿⣿⠟⠙⢿⣿⡿⠋⠘⢿⣿⡿⠛⢿⣿⡿⠋⠀⠻⣿⣿⠟⠁⠀⠀⠘⢿⣿⠟⠁⣴⣿⣿⠿⠋⠙⢿⡿⠟⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
**/
contract FishContract is ERC721A,  ERC721AQueryable, Ownable, ReentrancyGuard {
    using ECDSA for bytes32;
    using SafeMath for uint256;
    using Strings for uint256;
    uint256 public constant MAX_SUPPLY = 4444;
    uint256 public constant MAX_SALE_SUPPLY = 4444;
    uint8 public  maxByWalletPerPublic = 3;
    uint8 public  maxByWalletPerfFishSale = 1;

    uint256 public  MINT_PRICE = 0.009 ether;

    enum Stage {
        SaleClosed,
        FishList,
        Public
    }

    enum Evolution {
        First,
        Second
    }

    Stage public saleState = Stage.SaleClosed;
    Evolution public evolutionState = Evolution.First;

    string public baseTokenURI;
    string public notRevealedUri;
    string public baseExtension = ".json";

    bool public revealed = false;

    bytes32 private _fishListMerkleRoot;

    constructor() ERC721A("FishMafia", "FISH") {}


    function evolution(string memory _evolutionURI, Evolution _evolutionState) public onlyOwner {
        evolutionState = _evolutionState;
        baseTokenURI = _evolutionURI;
    }

    ////////////////////
    // MINT FUNCTIONS //
    ////////////////////

    function mint(uint8 _amountOfFish, bytes32[] memory _proof) public payable mintIsOpen nonContract nonReentrant{
        require(totalSupply() + _amountOfFish <= MAX_SALE_SUPPLY, "Reached Max Supply");
        require(MINT_PRICE * _amountOfFish <= msg.value, "Ether value sent is not correct");
        if (saleState == Stage.FishList) {
            require(_fishListMerkleRoot != "", "Fish Claim merkle tree not set. This address is not allowed to mint");
            require(MerkleProof.verify(_proof, _fishListMerkleRoot,
                keccak256(abi.encodePacked(msg.sender))),
                "FishList claim validation failed.");
            _fishListMint(_amountOfFish);
        }
        if (saleState == Stage.Public) {
            _publicMint(_amountOfFish);
        }
    }

    function _publicMint(uint8 _amountOfFish) internal mintIsOpen {
        require(saleState == Stage.Public, "Public mint is not open yet!");
        require(getRedemptionsPublic() + _amountOfFish <= maxByWalletPerPublic, "Exceeded max available to purchase");
        incrementRedemptionsPublic(_amountOfFish);
        _safeMint(msg.sender, _amountOfFish);
    }

    function _fishListMint(uint8 _amountOfFish) internal mintIsOpen {
        require(saleState == Stage.FishList, "FishList mint is not open yet!");
        require(getRedemptionsFishList() + _amountOfFish <= maxByWalletPerfFishSale, "Exceeded max available to purchase");
        incrementRedemptionsFishList(_amountOfFish);
        _safeMint(msg.sender, _amountOfFish);
    }


    ////////////////////
    // OWNER FUNCTIONS //
    ////////////////////

    function setMaxByWalletPerPublic(uint8 newMaxByWallet) external onlyOwner {
        maxByWalletPerPublic = newMaxByWallet;
    }

    function setMaxByWalletPerFishSale(uint8 newMaxByWallet) external onlyOwner {
        maxByWalletPerfFishSale = newMaxByWallet;
    }


    function setFishListMerkleRoot(bytes32 newMerkleRoot_) external onlyOwner {
        _fishListMerkleRoot = newMerkleRoot_;
    }

    function setStage(Stage _saleState) public onlyOwner {
        saleState = _saleState;
    }

    function setReveal(bool _setReveal) public onlyOwner {
        revealed = _setReveal;
    }

    function setBaseURI(string memory _baseTokenURI) public onlyOwner {
        baseTokenURI = _baseTokenURI;
    }

    function setNotRevealedURI(string memory _notRevealedURI) public onlyOwner {
        notRevealedUri = _notRevealedURI;
    }

    function reserveMint(address to, uint8 _amountOfFish) public onlyOwner nonReentrant mintIsOpen{
        require(totalSupply() + _amountOfFish <= MAX_SUPPLY, "Reached Max Supply");
        _safeMint(to, _amountOfFish);
    }

    function airdrop(
        address[] calldata _addresses,
        uint8 _amountOfFish
    ) external onlyOwner nonReentrant mintIsOpen {
        require(totalSupply() + _amountOfFish * _addresses.length  <= MAX_SUPPLY, "Reached Max Supply");
        for (uint256 i = 0; i < _addresses.length; i++) {
            _safeMint(_addresses[i], _amountOfFish);
        }
    }

    function withdraw() public onlyOwner nonReentrant {
        require(saleState == Stage.SaleClosed, "Sorry, but not now");
        (bool success,) = msg.sender.call{value : address(this).balance}("");
        require(success, "Transfer failed.");
    }


    function decrease(uint256 _newValue) public onlyOwner nonReentrant mintIsOpen {
        MINT_PRICE = _newValue;
    }
    ////////////////////
    // OVERRIDES //
    ////////////////////

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function tokenURI(uint256 tokenId)
    public
    view
    virtual
    override(ERC721A, IERC721A)
    returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        string memory currentBaseURI = _baseURI();

        if(revealed == false) {
            currentBaseURI = notRevealedUri;
        }

        return
        bytes(currentBaseURI).length > 0
        ? string(abi.encodePacked(currentBaseURI, tokenId.toString(), baseExtension))
        : "";
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    /********************  READ ********************/

    function numberMinted(address owner) public view returns (uint256) {
        return _numberMinted(owner);
    }

    function nextTokenId() public view returns (uint256) {
        return _nextTokenId();
    }

    function baseURI() public view returns (string memory) {
        return _baseURI();
    }

    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    function toString(uint256 x) public pure returns (string memory) {
        return _toString(x);
    }

    function getOwnershipOf(uint256 index) public view returns (TokenOwnership memory) {
        return _ownershipOf(index);
    }

    function getOwnershipAt(uint256 index) public view returns (TokenOwnership memory) {
        return _ownershipAt(index);
    }

    function totalMinted() public view returns (uint256) {
        return _totalMinted();
    }

    function totalBurned() public view returns (uint256) {
        return _totalBurned();
    }

    function numberBurned(address owner) public view returns (uint256) {
        return _numberBurned(owner);
    }

    function getAvailableForMintByCurrentStage(address checkedAddress) public view returns (uint8) {
        (uint8 vipListMintRedemptions,uint8 fishListMintRedemptions, uint8 publicListMintRedemptions) = unpackMintRedemptions(
            _getAux(checkedAddress)
        );
        if(saleState==Stage.FishList)
            return maxByWalletPerfFishSale - fishListMintRedemptions;
        if(saleState==Stage.Public)
            return maxByWalletPerPublic - publicListMintRedemptions;
        return 0;
    }


    /********************  MODIFIERS ********************/

    modifier mintIsOpen() {
        require(totalSupply() <= MAX_SUPPLY, "Soldout!");
        require(
            saleState != Stage.SaleClosed,
            "Mint is not open yet!"
        );
        _;
    }

    modifier nonContract() {
        require(tx.origin == msg.sender, "No, no, no. ! It is forbidden!");
        _;
    }

    //////////////////////
    // GETTER FUNCTIONS //
    //////////////////////

    /**
     * @notice Unpack and get number of viplist token mints redeemed by caller
     * @return number of allowlist redemptions used
     * @dev Number of redemptions are stored in ERC721A auxillary storage, which can help
     * remove an extra cold SLOAD and SSTORE operation. Since we're storing two values
     * (vip, public and fishlist redemptions) we need to pack and unpack three uint8s into a single uint24.
     * See https://chiru-labs.github.io/ERC721A/#/erc721a?id=addressdata
     */
    function getRedemptionsVipList() private view returns (uint8) {
        (uint8 vipListMintRedemptions,,) = unpackMintRedemptions(
            _getAux(msg.sender)
        );
        return vipListMintRedemptions;
    }

    /**
     * @notice Unpack and get number of fishlist token mints redeemed by caller
     * @return number of allowlist redemptions used
     * @dev Number of redemptions are stored in ERC721A auxillary storage, which can help
     * remove an extra cold SLOAD and SSTORE operation. Since we're storing two values
     * (vip, public and fishlist redemptions) we need to pack and unpack three uint8s into a single uint24.
     * See https://chiru-labs.github.io/ERC721A/#/erc721a?id=addressdata
     */
    function getRedemptionsFishList() private view returns (uint8) {
        (,uint8 fishListMintRedemptions,) = unpackMintRedemptions(
            _getAux(msg.sender)
        );
        return fishListMintRedemptions;
    }


    /**
     * @notice Unpack and get number of fishlist token mints redeemed by caller
     * @return number of allowlist redemptions used
     * @dev Number of redemptions are stored in ERC721A auxillary storage, which can help
     * remove an extra cold SLOAD and SSTORE operation. Since we're storing two values
     * (vip, public and fishlist redemptions) we need to pack and unpack three uint8s into a single uint24.
     * See https://chiru-labs.github.io/ERC721A/#/erc721a?id=addressdata
     */
    function getRedemptionsPublic() private view returns (uint8) {
        (,,uint8 publicMintRedemptions) = unpackMintRedemptions(
            _getAux(msg.sender)
        );
        return publicMintRedemptions;
    }

    //////////////////////
    // HELPER FUNCTIONS //
    //////////////////////
    /**
     * @notice Pack three uint8s (viplist, allowlist and public redemptions) into a single uint24 value
     * @return Packed value
     * @dev Performs shift and bit operations to pack two uint8s into a single uint24
     */
    function packMintRedemptions(
        uint8 _vipMintRedemptions,
        uint8 _fishListMintRedemptions,
        uint8 _publicMintRedemptions
    ) private pure returns (uint24) {
        return
        (uint24(_vipMintRedemptions) << 8) |
        (uint24(_fishListMintRedemptions) << 16) | uint24(_publicMintRedemptions);
    }

    /**
     * @notice Unpack a single uint24 value into thr uint8s (vip, fishList and public redemptions)
     * @return vipMintRedemptions fishListMintRedemptions publicMintRedemptions Unpacked values
     * @dev Performs shift and bit operations to unpack a single uint64 into two uint32s
     */
    function unpackMintRedemptions(uint64 _mintRedemptionPack)
    private
    pure
    returns (uint8 vipMintRedemptions, uint8 fishListMintRedemptions, uint8 publicMintRedemptions)
    {
        vipMintRedemptions = uint8(_mintRedemptionPack >> 8);
        fishListMintRedemptions = uint8(_mintRedemptionPack >> 16);
        publicMintRedemptions = uint8(_mintRedemptionPack);
    }

    /**
    * @notice Increment number of viplist token mints redeemed by caller
     * @dev We cast the _numToIncrement argument into uint8, which will not be an issue as
     * mint quantity should never be greater than 2^8 - 1.
     * @dev Number of redemptions are stored in ERC721A auxillary storage, which can help
     * remove an extra cold SLOAD and SSTORE operation. Since we're storing two values
     * (vip, fishlist and public) we need to pack and unpack two uint8s into a single uint64.
     * See https://chiru-labs.github.io/ERC721A/#/erc721a?id=addressdata
     */
    function incrementRedemptionsVipList(uint8 _numToIncrement) private {
        (
        uint8 vipListMintRedemptions,
        uint8 fishListMintRedemptions,
        uint8 publicMintRedemptions
        ) = unpackMintRedemptions(_getAux(msg.sender));
        vipListMintRedemptions += uint8(_numToIncrement);
        _setAux(
            msg.sender,
            packMintRedemptions(vipListMintRedemptions, fishListMintRedemptions, publicMintRedemptions)
        );
    }

    /**
    * @notice Increment number of fishlist token mints redeemed by caller
     * @dev We cast the _numToIncrement argument into uint8, which will not be an issue as
     * mint quantity should never be greater than 2^8 - 1.
     * @dev Number of redemptions are stored in ERC721A auxillary storage, which can help
     * remove an extra cold SLOAD and SSTORE operation. Since we're storing two values
     * (vip, fishlist and public redemptions) we need to pack and unpack two uint8s into a single uint64.
     * See https://chiru-labs.github.io/ERC721A/#/erc721a?id=addressdata
     */
    function incrementRedemptionsFishList(uint8 _numToIncrement) private {
        (
        uint8 vipListMintRedemptions,
        uint8 fishListMintRedemptions,
        uint8 publicMintRedemptions
        ) = unpackMintRedemptions(_getAux(msg.sender));
        fishListMintRedemptions += uint8(_numToIncrement);
        _setAux(
            msg.sender,
            packMintRedemptions(vipListMintRedemptions, fishListMintRedemptions, publicMintRedemptions)
        );
    }

    /**
     * @notice Increment number of public token mints redeemed by caller
     * @dev We cast the _numToIncrement argument into uint8, which will not be an issue as
     * mint quantity should never be greater than 2^8 - 1.
     * @dev Number of redemptions are stored in ERC721A auxillary storage, which can help
     * remove an extra cold SLOAD and SSTORE operation. Since we're storing two values
     * (vip, fishlist and public) we need to pack and unpack two uint8s into a single uint64.
     * See https://chiru-labs.github.io/ERC721A/#/erc721a?id=addressdata
     */
    function incrementRedemptionsPublic(uint8 _numToIncrement) private {
        (
        uint8 vipListMintRedemptions,
        uint8 fishListMintRedemptions,
        uint8 publicMintRedemptions
        ) = unpackMintRedemptions(_getAux(msg.sender));
        publicMintRedemptions += uint8(_numToIncrement);
        _setAux(
            msg.sender,
            packMintRedemptions(vipListMintRedemptions, fishListMintRedemptions, publicMintRedemptions)
        );
    }

    /**
   * @notice Prevent accidental ETH transfer
     */
    fallback() external payable {
        revert NotImplemented();
    }

    /**
     * @notice Prevent accidental ETH transfer
     */
    receive() external payable {
        revert NotImplemented();
    }

}

/**
 * Function not implemented
 */
    error NotImplemented();
