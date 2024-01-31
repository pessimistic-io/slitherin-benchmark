// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/*
███████╗ ██████╗ ██████╗  ██████╗███████╗██████╗      ██████╗ ███████╗███████╗██╗     ██╗███╗   ██╗███████╗
██╔════╝██╔═══██╗██╔══██╗██╔════╝██╔════╝██╔══██╗    ██╔═══██╗██╔════╝██╔════╝██║     ██║████╗  ██║██╔════╝
█████╗  ██║   ██║██████╔╝██║     █████╗  ██║  ██║    ██║   ██║█████╗  █████╗  ██║     ██║██╔██╗ ██║█████╗
██╔══╝  ██║   ██║██╔══██╗██║     ██╔══╝  ██║  ██║    ██║   ██║██╔══╝  ██╔══╝  ██║     ██║██║╚██╗██║██╔══╝
██║     ╚██████╔╝██║  ██║╚██████╗███████╗██████╔╝    ╚██████╔╝██║     ██║     ███████╗██║██║ ╚████║███████╗
╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚══════╝╚═════╝      ╚═════╝ ╚═╝     ╚═╝     ╚══════╝╚═╝╚═╝  ╚═══╝╚══════╝
*/

import "./CountersUpgradeable.sol";
import "./Initializable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./IERC721EnumerableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./ERC721BurnableUpgradeable.sol";
import "./ERC721PausableUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./ContextUpgradeable.sol";
import "./MerkleProofUpgradeable.sol";
import { Base64 } from "./base64.sol";
import "./UUPSUpgradeable.sol";
import "./IRandomConsumer.sol";
import "./IRandomGenerator.sol";
import "./IForcedOffline.sol";

contract MysteryBox is
Initializable,
UUPSUpgradeable,
ContextUpgradeable,
AccessControlEnumerableUpgradeable,
ERC721EnumerableUpgradeable,
ERC721BurnableUpgradeable,
ERC721PausableUpgradeable,
ERC721HolderUpgradeable,
IRandomConsumer
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using AddressUpgradeable for address;
    using StringsUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /*//////////////////////////////////////////////////////////////
                               ADDRESSES
    //////////////////////////////////////////////////////////////*/
    IForcedOffline public nftToken;

    IRandomGenerator public randomGenerator;

    /*//////////////////////////////////////////////////////////////
                              MINTING STATE
    //////////////////////////////////////////////////////////////*/
    CountersUpgradeable.Counter private _tokenIdTracker;

    bytes32 public merkleRoot;

    uint public totalMysteryBoxQuota;
    uint public totalMysteryBoxSold;

    mapping (address => uint) public whitelistBuyingHistory;
    bool public whiteListOnly;
    uint public whiteListBuyableQuota;

    EnumerableSetUpgradeable.AddressSet private publicBuyerList;
    mapping (address => uint) public publicBuyingHistory;
    uint public publicBuyableQuota;

    bool public isMintingStarted;

    string public imageUrl;

    /*//////////////////////////////////////////////////////////////
                              REVEALING STATE
    //////////////////////////////////////////////////////////////*/
    EnumerableSetUpgradeable.UintSet private nftIds;
    bool public isRevealingStarted;


    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event SetRandomGenerator(IRandomGenerator _newRandomGenerator);
    event SetNftToken(IForcedOffline _newNft);
    event Mint(address _to, uint tokenid_);
    event MintMulti(address indexed _to, uint _amount);
    event RevealRequested(uint indexed tokenId, address indexed user_);
    event Reveal(uint indexed tokenId_, uint indexed nftId_);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyEOA() {
        require(msg.sender == tx.origin, "MysteryBox: not eoa");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE` to the
     * account that deploys the contract.
     */
    constructor() {}

    function initialize(IForcedOffline nftToken_, IRandomGenerator randomGenerator_, uint totalQuota_)
        public initializer {
        __AccessControlEnumerable_init();
        __ERC721_init_unchained("ForcedOffline Mystery Box", "FOBOX");
        __ERC721Enumerable_init_unchained();
        __ERC721Burnable_init_unchained();
        __Pausable_init_unchained();
        __ERC721Pausable_init_unchained();
        __ERC721Holder_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());

        require(hasRole(ADMIN_ROLE, _msgSender()), "MysteryBox: must have admin role to initialize.");

        nftToken = nftToken_;
        randomGenerator = randomGenerator_;

        whiteListBuyableQuota = 3;
        publicBuyableQuota = 3;
        totalMysteryBoxQuota = totalQuota_;

        isMintingStarted = false;
        whiteListOnly = true;
        isRevealingStarted = false;
    }

    /*//////////////////////////////////////////////////////////////
                          CONFIGURATION LOGIC
    //////////////////////////////////////////////////////////////*/
    function setRandomGenerator(IRandomGenerator randomGenerator_) onlyRole(ADMIN_ROLE) whenPaused public {
        require(randomGenerator_ != IRandomGenerator(address(0)), "The address of random generator is null");
        randomGenerator = randomGenerator_;
        emit SetRandomGenerator(randomGenerator_);
    }

    function setNftToken(IForcedOffline nftToken_) onlyRole(ADMIN_ROLE) whenPaused public {
        require(nftToken_ != IForcedOffline(address(0)), "The address of IERC721 token is null");
        nftToken = nftToken_;
        emit SetNftToken(nftToken_);
    }

    function setWhiteListBuyableQuota(uint whiteListBuyableQuota_) onlyRole(ADMIN_ROLE) whenPaused external {
        whiteListBuyableQuota = whiteListBuyableQuota_;
    }

    function setPublicBuyableQuota(uint publicBuyableQuota_) onlyRole(ADMIN_ROLE) whenPaused external {
        publicBuyableQuota = publicBuyableQuota_;
    }

    function setTotalQuota(uint totalQuota_) onlyRole(ADMIN_ROLE) whenPaused external {
        totalMysteryBoxQuota = totalQuota_;
    }

    function setMerkleRoot(bytes32 merkleRoot_) onlyRole(ADMIN_ROLE) whenPaused external {
        merkleRoot = merkleRoot_;
    }

    /*//////////////////////////////////////////////////////////////
                               MINTING LOGIC
    //////////////////////////////////////////////////////////////*/
    function mintMulti(bytes32[] calldata merkleProof, uint amount) whenNotPaused onlyEOA external {
        require(isMintingStarted, "Minting has not started yet");
        require(amount > 0, "MysteryBox: missing amount");
        totalMysteryBoxSold += amount;
        require(totalMysteryBoxSold <= totalMysteryBoxQuota, "MysteryBox: exceeded total mystery box buyable quota.");

        if (whiteListOnly) {
            require(MerkleProofUpgradeable.verify(merkleProof, merkleRoot, toBytes32(msg.sender)) == true,
                "only whitelist allowed");
            require(whitelistBuyingHistory[_msgSender()] + amount <= whiteListBuyableQuota,"Out of whitelist quota");
            whitelistBuyingHistory[_msgSender()] += amount;
        } else {
            require(publicBuyingHistory[_msgSender()] + amount <= publicBuyableQuota, "Out of public sell quota");
            publicBuyingHistory[_msgSender()] += amount;
            publicBuyerList.add(_msgSender());
        }
        for (uint i = 0; i < amount; i++) {
            _mint(_msgSender(), _tokenIdTracker.current());
            emit Mint(_msgSender(),_tokenIdTracker.current());
            _tokenIdTracker.increment();
        }
        emit MintMulti(_msgSender(), amount);
    }

    function toggleWhiteListOnly() onlyRole(ADMIN_ROLE) whenPaused external {
        if (whiteListOnly) {
            whiteListOnly = false;
        } else {
            whiteListOnly = true;
        }
    }

    /*//////////////////////////////////////////////////////////////
                           REVEALING LOGIC
    //////////////////////////////////////////////////////////////*/
    function reveal(uint tokenId_) whenNotPaused onlyEOA external {
        require(isRevealingStarted, "Revealing has not started yet.");
        require(_isApprovedOrOwner(_msgSender(), tokenId_), "MysteryBox: caller is not owner nor approved");
        randomGenerator.requestRandomNumber(tokenId_, _msgSender());
        approve(address(randomGenerator), tokenId_);
        emit RevealRequested(tokenId_, _msgSender());
    }

    function revealAll(uint from_, uint to_) onlyRole(ADMIN_ROLE) whenNotPaused external {
        for(uint i = from_; i < to_; i++) {
            if(!_exists(i)) {
                continue;
            }
            address _user = ownerOf(i);
            // no need user approval
            _burn(i);
            _fulfillReveal(i, _user, _randModulus(_user, block.timestamp, type(uint).max));
        }
    }

    function runFulfillRandomness(uint256 tokenId_, address user_, uint256 randomness_) external {
        require(_msgSender() == address(randomGenerator),
            "MysteryBox: only selected generator can call this method"
        );
        fulfillRandomness(tokenId_, user_, randomness_);
    }

    function fulfillRandomness(uint256 tokenId_, address user_, uint256 randomness_) internal {
        require(_isApprovedOrOwner(user_, tokenId_), "MysteryBox: user is not owner nor approved");
        burn(tokenId_);
        _fulfillReveal(tokenId_, user_, randomness_);
    }

    function _randModulus(address user_, uint seed_, uint mod_) internal view returns (uint) {
        uint rand = uint(keccak256(abi.encodePacked(
                block.timestamp,
                block.difficulty,
                mod_,
                user_,
                seed_,
                _msgSender())
            )) % mod_;
        return rand;
    }

    function _fulfillReveal(uint256 tokenId_, address user_, uint256 randomness_) internal {
        uint index = uint(keccak256(abi.encodePacked(randomness_))) % nftIds.length();
        uint nftId = nftIds.at(index);
        nftIds.remove(nftId);
        nftToken.reveal(nftId);
        IERC721Upgradeable(address(nftToken)).transferFrom(address(this), user_, nftId);
        emit Reveal(tokenId_, nftId);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/
    function transferAdmin(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(DEFAULT_ADMIN_ROLE, account);
        revokeRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function cleanPublicBuyHistory(uint amount) onlyRole(ADMIN_ROLE) whenPaused public returns (bool) {
        uint length = publicBuyerList.length();
        if (length < amount) {
            amount = length;
        }
        for (uint i = 0; i < amount; i++) {
            // modify fixed 0 position while iterating all keys
            address buyer = publicBuyerList.at(0);
            delete publicBuyingHistory[buyer];
            publicBuyerList.remove(buyer);
        }
        return true;
    }

    function pause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "MysteryBox: must have pauser role to pause.");
        _pause();
    }

    function unpause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "MysteryBox: must have pauser role to unpause");
        _unpause();
    }

    function pullNFTs(address tokenAddress, address receivedAddress, uint amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(receivedAddress != address(0));
        require(tokenAddress != address(0));
        uint balance = IERC721Upgradeable(tokenAddress).balanceOf(address(this));
        if (balance < amount) {
            amount = balance;
        }
        for (uint i = 0; i < amount; i++) {
            uint tokenId = IERC721EnumerableUpgradeable(tokenAddress).tokenOfOwnerByIndex(address(this), 0);
            IERC721Upgradeable(tokenAddress).safeTransferFrom(address(this), receivedAddress, tokenId);
        }
    }

    function resetNftIds(uint[] calldata nftIds_) public onlyRole(ADMIN_ROLE) {
        clearNftIds();
        for (uint i = 0; i < nftIds_.length; i++) {
            nftIds.add(nftIds_[i]);
        }
    }

    function initializeNftIds() external whenPaused onlyRole(ADMIN_ROLE) {
        clearNftIds();
        for (uint i = 0; i < totalMysteryBoxQuota; i++) {
            nftIds.add(i);
        }
    }

    function clearNftIds() internal {
        uint length = nftIds.length();
        for (uint i = 0; i < length; i++) {
            nftIds.remove(nftIds.at(0));
        }
    }

    /*//////////////////////////////////////////////////////////////
                             URI LOGIC
    //////////////////////////////////////////////////////////////*/
    function tokenURI(uint256 tokenId_) public view override returns (string memory) {
        require(_exists(tokenId_), 'URI query for nonexistent token.');
        return constructTokenURI();
    }

    function constructTokenURI() public view returns (string memory) {
        bytes memory metadata = abi.encodePacked('{"name":"',
            "Ultra Mystery Box",
            '","description":"',
            "A mystery loot box",
            '","image": "',
            imageUrl,
            '"}');

        return string(
            abi.encodePacked(
                'data:application/json;base64,',
                Base64.encode(
                    bytes(metadata)
                )
            )
        );
    }

    function setImageUrl(string calldata imageUrl_) external onlyRole(ADMIN_ROLE) {
        imageUrl = imageUrl_;
    }

    /*//////////////////////////////////////////////////////////////
                          ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override (ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721PausableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(AccessControlEnumerableUpgradeable, ERC721Upgradeable, ERC721EnumerableUpgradeable)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                          PHASES CONTROL LOGIC
    //////////////////////////////////////////////////////////////*/
    function startWhiteListMinting() onlyRole(ADMIN_ROLE) whenPaused external {
        isMintingStarted = true;
        whiteListOnly = true;
    }

    function startPublicMinting() onlyRole(ADMIN_ROLE) whenPaused  external {
        isMintingStarted = true;
        whiteListOnly = false;
    }

    function startRevealing() onlyRole(ADMIN_ROLE) whenPaused  external {
        isRevealingStarted = true;
    }

    function endAll() onlyRole(ADMIN_ROLE) whenPaused  external {
        isMintingStarted = false;
        isRevealingStarted = false;
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function totalSold() external view returns(uint) {
        return totalMysteryBoxSold;
    }

    function totalQuota() external view returns(uint) {
        return totalMysteryBoxQuota;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function toBytes32(address addr) pure internal returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}

