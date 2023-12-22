// SPDX-License-Identifier: MIT

//,,,,,,,,,,,,,,,,,,,***************************************,*,,,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,,,,,,**,,,,***********************,*,,,,,,,,,,,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,****,,,*,,,**,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,*.,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,((*,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,*%%#(*/&%( #( %#.,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,*###(*....         #(,,,,,,,,,,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,(###(,,...          .,,,,,,,,,,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,.,(#%%(*,,,...         ,,,,,,,,,,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,/#%%%#**,,,,,... ,,   ,,,,,,,,,,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,/###((/**,,,,*,,,,,*.  ,,,,,,,,,,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,,,,,,,,,,,,,(##((#%%%%%##//##((/( ,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,,,,,,,,,,,,,,*((/*........      .,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,,,,,,,,,,,,,(%&&&&&&&&&&&&&%%%%%%%%%#/,,,,,,,,,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,,,,,,,,,,,********,,,....                ,,,,,,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,#(/,,,,,,*@%(#%%%%%&&&&&&&&%%%%%%%(((//,..  /,,,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,##(/,,&&&&&&&&&&&&&&&&&&&&&%%%%%%%%%%%%%%%%%/*,,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,,##,.,*/((##(((//****,,,....                  .,,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,,((* .(####(***,,,,,#%%%%%%%%%%%%%#####%%%%%%((/,,,,,,,,,,,,,,,,
//,,,,,,,,,,,,,,,,*&(%%#%%%%###(((((//#%%%######%%%%%%%###########, ,,,,,,,,,,,,,,
//*,,,,,,,,,,,,,,,,((%%%%%%%%###((((//#%%#(    .(##%########(/   (. ,,,,,,,,,,,,,,
//*,*,,,,,,,,,,,,,,/#%%%%%%%####((((//#%%#(    ,(#####   .(#(/   (. ,,,,,,,,,,,,,,
//*******,,,,,*/ .,(&(#%%%%%%###((((//#%%%%#####%%%%%%%%%%%#######, ,,,,,,,,,,,,,,
//********,*,///  ,/##&####(///*****(##%%%%%%%%%%%%%%%%%%%%%%##### ,,,,,,,,,,,,,,,
//********,*/(//  ,,##/.,,,,,,,,,,,,,,,,,*((*,,,,,,,,,,,,(     .*.,,,,,,,,,,,,,,,,
//**********(((*   *,,,..*(/,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,#(#(/,   ,,,,,,,,,,,,,,,
//*********&&&%*,  ,**((((#(//,/(%&&&%/*,   .%%%%%   ,*,#%## ((,,  (#/,,,,,,,,,,,,
//*********&&&&(##((,.,%%%%(*. ,#%##&&&&((    #%%%%.   ##%/.#/,   *,.. .,,,,,,,,,,
//*********@@@&#%(/*,..%@&%#/, .%%###((*, (&& . .**/(&&     /#(.  (*,. .,,,,,,,*,,
//********(@@@&#%(/*,..***/%%#* .%%%###((////*  %#((((///* .*%#/  #/*,..*,,,,*****
//********(&&@&#%(/*,.*******#.((%%%%%##////((((%#(/**//((((*,%%%#%(*,.***********
//*********#####%(/*,,*******#*(%%%%%%%########***%%%%%%%#/****%%#%%/,,,**********
//                      ____   ____  ____   ____ _______ _____                  //
//                     |  _ \ / __ \|  _ \ / __ \__   __/ ____|                 //
//                     | |_) | |  | | |_) | |  | | | | | (___                   //
//                     |  _ <| |  | |  _ <| |  | | | |  \___ \                  //
//                     | |_) | |__| | |_) | |__| | | |  ____)                   //
//                     |____/ \____/|____/ \____/  |_| |_____/                  //
//////////////////////////////////////////////////////////////////////////////////
pragma solidity ^0.8.13;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./MerkleProof.sol";
import "./Math.sol";
import "./StringsUpgradeable.sol";

//other staking contracts
import "./IBobot.sol";
import "./InstallationCoreChamber.sol";


contract BobotGenesis is IBobot, ERC721EnumerableUpgradeable, OwnableUpgradeable 
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using StringsUpgradeable for uint256;

    //revealed and unrevealed uri
    string public baseRevealedURI;
    string public baseHiddenURI;

    string public baseExtention;
    uint256 constant maxSupply = 4040;
    uint256 public maxLevelAmount;

    //reveal whitelist variables
    bool public revealed;

    //root hash for merkle proof
    bytes32 public rootGuardiansHash_1;
    bytes32 public rootGuardiansHash_2;
    bytes32 public rootLunarsHash;

    //core chamber level update cost
    uint256 public coreChamberLevelCost;

    //token id counter
    CountersUpgradeable.Counter private _tokenIdCounter;

    //level cost
    uint256 levelCost;

    //amount mintable per whitelist
    mapping(address => bool) public whitelistedAddressesClaimed;

    //core chamber
    CoreChamber public coreChamber;

    //is the contract mint running
    bool public paused;

    //core points on a per bobot basis
    //one bobot -> core point
    mapping(uint256 => uint256) public bobotCorePoints;


    function initialize() external initializer 
    {
        __ERC721Enumerable_init();
        __Ownable_init();

        baseExtention = ""; 
        maxLevelAmount = 10; 
        revealed = false; 
        paused = false;
    }
    
    //modifiers
    /**************************************************************************/
    /*!
       \brief only core chamber can access this function
    */
    /**************************************************************************/
    modifier onlyCoreChamber() {
        require(msg.sender == address(coreChamber), "Bobots: !CoreChamber");
        _;
    }

    /**************************************************************************/
    /*!
       \brief view URI reveal / hidden
    */
    /**************************************************************************/
    function _baseURI() internal view virtual override returns (string memory) {
        return revealed ? baseRevealedURI : baseHiddenURI; // return own base URI
    }

    // public
    /**************************************************************************/
    /*!
       \brief mint a bobot - multiple things to check 
       does user have $MAGIC in their wallet?
    */
    /**************************************************************************/
    function mintBobot(
        bytes32[] calldata _merkleProof
    ) public payable {
        //is contract running?
        require(!paused);
       
        uint256 mintCount = 0;
        
        //minter must be whitelisted

        // check if user already white listed either as a guardian or lunar
        require(
             whitelistedAddressesClaimed[msg.sender] == false,
            "user already whitelisted"
        );

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));

        bool isGuardiansGroup_1 = MerkleProof.verify( _merkleProof, rootGuardiansHash_1, leaf );
        bool isGuardiansGroup_2 = MerkleProof.verify( _merkleProof, rootGuardiansHash_2, leaf );
        bool isLunars = MerkleProof.verify(_merkleProof, rootLunarsHash, leaf);

        //check if leaf is valid
        require(
            isGuardiansGroup_1 || isGuardiansGroup_2 || isLunars,
            "Invalid proof - not whitelisted"
        );

        //guardians will have 1 mint
        //lunars will have 2 mint

        if (isGuardiansGroup_1 || isGuardiansGroup_2 ) {
            require(_getNextTokenId() <= maxSupply);
            mintCount = 1;
        }

        if (isLunars) {
            require(_getNextTokenId() + 1 <= maxSupply);
            mintCount = 2;
        }

        //user claimed WL
        whitelistedAddressesClaimed[msg.sender] = true;

        for (uint256 i = 1; i <= mintCount; ++i) {
            uint256 nextTokenId = _getNextTokenId();
            _safeMint(msg.sender, nextTokenId);
        }
    }
    /**************************************************************************/
    /*!
       \brief get bobots type
    */
    /**************************************************************************/

    function getBobotType()
        external
        view
        override
        returns (BobotType)
    {
        return BobotType.BOBOT_GEN;
    }

    /**************************************************************************/
    /*!
       \brief return all token ids a holder owns
    */
    /**************************************************************************/
    function getTokenIds(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 t = ERC721Upgradeable.balanceOf(_owner);
        uint256[] memory _tokensOfOwner = new uint256[](t);

        for (uint256 i = 0; i < ERC721Upgradeable.balanceOf(_owner); i++) {
            _tokensOfOwner[i] = ERC721EnumerableUpgradeable.tokenOfOwnerByIndex(
                _owner,
                i
            );
        }
        return (_tokensOfOwner);
    }

    /**************************************************************************/
    /*!
       \brief return URI of a token - could be revealed or hidden
    */
    /**************************************************************************/
    function getTokenURI(uint256 tokenID)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenID),
            "ERC721Metadata: URI query for nonexistent token"
        );

        string memory currentBaseURI = _baseURI();

        string memory revealedURI = string(
            abi.encodePacked(
                baseRevealedURI,
                tokenID.toString(),
                "/",
                getCurrentBobotLevel(tokenID).toString(),
                baseExtention
            )
        );

        return 
            bytes(currentBaseURI).length > 0
                ? (revealed ? revealedURI : baseHiddenURI)
                : "";
    }
    /**************************************************************************/
    /*!
       \brief return URI of a token - could be revealed or hidden
    */
    /**************************************************************************/
    function tokenURI(uint256 tokenID)
        public
        view
        virtual
        override
        returns (string memory)
    {
        return getTokenURI(tokenID);
    }
    /**************************************************************************/
    /*!
       \brief get next token id
    */
    /**************************************************************************/
    function _getNextTokenId() private view returns (uint256) {
        return (_tokenIdCounter.current() + 1);
    }
    /**************************************************************************/
    /*!
       \brief safe mint
    */
    /**************************************************************************/
    function _safeMint(address to, uint256 tokenId)
        internal
        override(ERC721Upgradeable)
    {
        super._safeMint(to, tokenId);
        _tokenIdCounter.increment();
    }

    /**************************************************************************/
    /*!
       \brief returns the bobots current level
    */
    /**************************************************************************/
    function getCurrentBobotLevel(uint256 _tokenID) 
        public 
        view 
        returns (uint256)
    {
        return  Math.min(
            bobotCorePoints[_tokenID] / coreChamberLevelCost,
            maxLevelAmount
        );
    }
    /**************************************************************************/
    /*!
       \brief check if WL is claimed
    */
    /**************************************************************************/
    function checkClaimed(address _claimed) external view  returns (bool) {
       return whitelistedAddressesClaimed[_claimed];
    }
    /**************************************************************************/
    /*!
       \brief earning core points logic
    */
    /**************************************************************************/
    function coreChamberCorePointUpdate(uint256 _tokenId, uint256 _coreEarned)
        external
        onlyCoreChamber
    {
        bobotCorePoints[_tokenId] += _coreEarned;
    }

    //------------------------- ADMIN FUNCTIONS -----------------------------------


    /**************************************************************************/
    /*!
       \brief airdrop
    */
    /**************************************************************************/

    function airdrop(address _to, uint256 _amount) public onlyOwner
    {
        require(_getNextTokenId() + _amount < maxSupply);
        for (uint256 i = 1; i <= _amount; ++i) 
        {
            uint256 nextTokenId = _getNextTokenId();
            _safeMint(_to, nextTokenId);
        }
    }

    /**************************************************************************/
    /*!
       \brief set merkleproof hash
    */
    /**************************************************************************/
    function setRootGuardiansHash_1(bytes32 _rootHash) external onlyOwner {
        rootGuardiansHash_1 = _rootHash;
    }
    /**************************************************************************/
    /*!
       \brief set merkleproof hash
    */
    /**************************************************************************/
    function setRootGuardiansHash_2(bytes32 _rootHash) external onlyOwner {
        rootGuardiansHash_2 = _rootHash;
    }
    /**************************************************************************/
    /*!
       \brief set merkleproof hash
    */
    /**************************************************************************/
    function setRootLunarsHash(bytes32 _rootHash) external onlyOwner {
        rootLunarsHash = _rootHash;
    }

    /**************************************************************************/
    /*!
       \brief enable reveal phase
    */
    /**************************************************************************/
    function reveal(bool _revealed) external onlyOwner {
        revealed = _revealed;
    }
    /**************************************************************************/
    /*!
       \brief set core chamber level up cost
    */
    /**************************************************************************/
    function setCoreChamberLevelCost(uint256 _cost) external onlyOwner {
        coreChamberLevelCost = _cost;
    }
    /**************************************************************************/
    /*!
       \brief set Core Chamber Contract
    */
    /**************************************************************************/
    function setCoreChamber(address _coreChamber) external onlyOwner {
        coreChamber = CoreChamber(_coreChamber);
    }

    /**************************************************************************/
    /*!
       \brief set base URI
    */
    /**************************************************************************/
    function setBaseRevealedURI(string memory _newBaseURI) public onlyOwner {
        baseRevealedURI = _newBaseURI;
    }

    /**************************************************************************/
    /*!
       \brief set base URI
    */
    /**************************************************************************/
    function setBaseHiddenURI(string memory _newBaseURI) public onlyOwner {
        baseHiddenURI = _newBaseURI;
    }
    /**************************************************************************/
    /*!
       \brief set Base Extensions
    */
    /**************************************************************************/
    function setBaseExtentions(string memory _newBaseExtentions)
        public
        onlyOwner
    {
        baseExtention = _newBaseExtentions;
    }
    /**************************************************************************/
    /*!
       \brief before token transfer
    */
    /**************************************************************************/
    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _tokenId
    ) internal override {

        super._beforeTokenTransfer(_from, _to, _tokenId);

        if (address(coreChamber) != address(0))
            require(!coreChamber.isAtCoreChamberGenesis(_tokenId), "Genesis: at core chamber. Unstake to transfer.");
    }

    /**************************************************************************/
    /*!
       \brief set Max Level
    */
    /**************************************************************************/
    function setMaxLevel(uint256 _newLevelAmount)
        public
        onlyOwner
    {
        maxLevelAmount = _newLevelAmount;
    }

    /**************************************************************************/
    /*!
       \brief pause smart contract (for safety purposes)
    */
    /**************************************************************************/
    function pause(bool _state) public onlyOwner {
        paused = _state;
    }
}

