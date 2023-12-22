// SPDX-License-Identifier: MIT
// Creator: base64.tech
pragma solidity ^0.8.13;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./SamuRiseLandErrors.sol";

interface ISamuRiseLandMetadataState {
    function getMetadata(uint256 _tokenId) external view returns (string memory);
}

contract SamuRiseLandV2 is ERC721EnumerableUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using ECDSAUpgradeable for bytes32;
    using StringsUpgradeable for uint256;

    // +1 in these constants used for gas optimization 
    // for use in conditional statements
    uint256 public constant TOTAL_MAX_SUPPLY = 10020 + 1; 
    uint256 public constant MAX_LAND_PER_WALLET = 1 + 1; 
       
    // ENUM to determine which mint phase we are performing
    enum MintState{ INACTIVE, CLAIM_PERIOD, POST_CLAIM }

    enum DojoRarity{ YELLOW, ORANGE, BLUE, PURPLE, GREEN, RED, BROWN, BLACK }

    // Public key used to verify signatures
    address public signatureVerifier;

    // Sales state
    MintState public mintState;

    // Map to track used hashes
    mapping(bytes32 => bool) public usedHashes;

    // Map to track used hashes
    mapping(uint256 => DojoRarity) public tokenIdToRarity;

    // Maps to track number minted for each sale state
    mapping(address => uint256) public numberMinted;

    string private _baseTokenURI;

    bool private initialized;

    event LandRarity(uint256 tokenId, uint8 rarity);

    /* V2 variables */
    address public samuRiseLandMetadataStateContract;

    function initialize() public initializer {
        require(!initialized, "Contract instance has already been initialized");
        initialized = true;
        __Ownable_init_unchained();
        __ERC721Enumerable_init();
        __ERC721_init("SAMURISELAND", "SamuRiseLand");
        __UUPSUpgradeable_init_unchained();
        mintState = MintState.INACTIVE;
    }

    /* FUNCTION MODIFIERS */
    modifier callerIsUser() {
        if(tx.origin != msg.sender) revert CallerIsAnotherContract();
        _;
    }

    modifier validateClaimPeriodActive() {
        if(mintState != MintState.CLAIM_PERIOD) revert ClaimPeriodIsNotActive();
        _;
    }

    modifier validatePostClaimPeriodActive() {
        if(mintState != MintState.POST_CLAIM) revert PostClaimPeriodIsNotActive();
        _;
    }


    modifier underMaxSupply(uint256 _quantity) {
        if(!(totalSupply() + _quantity < TOTAL_MAX_SUPPLY)) revert WouldExceedMaxSupply();
        _;
    }

    modifier numberMintedUnderAllocation(uint256 _currentNumberOfMints, uint256 _quantity, uint256 _allowance) {
        if(!(_currentNumberOfMints + _quantity < _allowance)) revert MintWouldExceedMaxAllocation();
        _;
    }

    modifier hasValidSignature(bytes memory _signature, bytes memory message) {
        bytes32 messageHash = ECDSAUpgradeable.toEthSignedMessageHash(keccak256(message));
        require(messageHash.recover(_signature) == signatureVerifier, "Unrecognizable Hash");
        require(!usedHashes[messageHash], "Hash has already been used");

        usedHashes[messageHash] = true;
        _;
    }

    modifier stakedSamuRiseIsNotZero(uint256 _stakedSamuRiseCount) {
        require(_stakedSamuRiseCount > 0, "Needs to have at least 1 staked token");
        _;
    }

    /* MINT FUNCTIONS */
    function mint(bytes memory _signature, uint256 _stakedSamuRiseCount, uint256 _nonce) 
        external 
        callerIsUser 
        validateClaimPeriodActive
        stakedSamuRiseIsNotZero(_stakedSamuRiseCount)
        underMaxSupply(1) 
        hasValidSignature(_signature, abi.encodePacked(msg.sender, uint256(MintState.CLAIM_PERIOD), _stakedSamuRiseCount, _nonce))
        numberMintedUnderAllocation(numberMinted[msg.sender], 1, MAX_LAND_PER_WALLET)
    {
        DojoRarity dojoRarity = getDojo(_stakedSamuRiseCount, _nonce);
        tokenIdToRarity[totalSupply()] = dojoRarity;
        numberMinted[msg.sender] += 1;
        _mint(msg.sender, totalSupply());
        emit LandRarity(totalSupply()-1, uint8(dojoRarity));
    }

    function mintPostClaim(bytes memory _signature, uint256 _nonce) 
        external 
        callerIsUser 
        validatePostClaimPeriodActive 
        underMaxSupply(1) 
        hasValidSignature(_signature, abi.encodePacked(msg.sender, uint256(MintState.POST_CLAIM), _nonce))
        numberMintedUnderAllocation(numberMinted[msg.sender], 1, MAX_LAND_PER_WALLET)
    {
        DojoRarity dojoRarity = DojoRarity.YELLOW;
        tokenIdToRarity[totalSupply()] = dojoRarity;
        numberMinted[msg.sender] += 1;
        _mint(msg.sender, totalSupply());
        emit LandRarity(totalSupply()-1, uint8(dojoRarity));
    }

    function getDojo(uint256 _stakedSamuRiseCount, uint256 _nonce) public view returns(DojoRarity) {
        uint diceRolls = getDiceRolls(_stakedSamuRiseCount, _nonce);

        if (_stakedSamuRiseCount >= 20) {
            if(diceRolls == 2 || diceRolls == 3) {
                return DojoRarity.RED;
            } else if(diceRolls >= 4 && diceRolls <= 6) {
                return DojoRarity.GREEN;
            } else if(diceRolls >= 6 && diceRolls <= 12) {
                return DojoRarity.PURPLE;
            } 
        } else if (_stakedSamuRiseCount >= 10) {
            if(diceRolls == 2) {
                return DojoRarity.RED;
            } else if(diceRolls >= 3 && diceRolls <= 4) {
                return DojoRarity.GREEN;
            } else if(diceRolls >= 5 && diceRolls <= 7) {
                return DojoRarity.PURPLE;
            } else if(diceRolls >= 8 && diceRolls <= 12) {
                return DojoRarity.BLUE;
            } 
        } else if (_stakedSamuRiseCount >= 5) {
            if(diceRolls == 2) {
                return DojoRarity.GREEN;
            } else if(diceRolls >= 3 && diceRolls <= 4) {
                return DojoRarity.PURPLE;
            } else if(diceRolls >= 5 && diceRolls <= 7) {
                return DojoRarity.BLUE;
            } else if(diceRolls >= 8 && diceRolls <= 12) {
                return DojoRarity.ORANGE;
            } 
        } else if (_stakedSamuRiseCount >= 3) {
            if(diceRolls == 2) {
                return DojoRarity.PURPLE;
            } else if(diceRolls >= 3 && diceRolls <= 4) {
                return DojoRarity.BLUE;
            } else if(diceRolls >= 5 && diceRolls <= 9) {
                return DojoRarity.ORANGE;
            } else if(diceRolls >= 10 && diceRolls <= 12) {
                return DojoRarity.YELLOW;
            } 
        } else if (_stakedSamuRiseCount == 2) {
            if(diceRolls >= 2 && diceRolls <= 3) {
                return DojoRarity.BLUE;
            } else if(diceRolls >= 4 && diceRolls <= 7) {
                return DojoRarity.ORANGE;
            } else if(diceRolls >= 8 && diceRolls <= 12) {
                return DojoRarity.YELLOW;
            } 
        } else if (_stakedSamuRiseCount >= 1) {
            if(diceRolls == 2) {
                return DojoRarity.BLUE;
            } else if(diceRolls == 3) {
                return DojoRarity.ORANGE;
            } else if(diceRolls >= 4 && diceRolls <= 12) {
                return DojoRarity.YELLOW;
            } 
        }
            return DojoRarity.YELLOW;
    } 

    function getDiceRolls(uint256 _stakedSamuRiseCount, uint256 _nonce) public view returns(uint) {
        uint dice1 = (uint(keccak256(
            abi.encode(
                msg.sender,
                tx.gasprice,
                block.number,
                block.timestamp,
                block.difficulty,
                blockhash(block.number - 1),
                address(this),
                _stakedSamuRiseCount
            ))))%6 + 1;
        uint dice2 = (uint(keccak256(
            abi.encode(
                msg.sender,
                address(this),
                block.difficulty,
                blockhash(block.number - 1),
                block.number,
                block.timestamp,
                tx.gasprice,
                _nonce
            ))))%6 + 1;
        return dice1 + dice2;
    }

    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        require(_exists(_tokenId), "ERC721Metadata: URI query for nonexistent token");

        return ISamuRiseLandMetadataState(samuRiseLandMetadataStateContract).getMetadata(_tokenId);
    }

    /* INTERNAL FUNCTIONS */ 

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }
    
    /* OWNER FUNCTIONS */

    function ownerMint(uint256 _numberToMint)
        external
        onlyOwner
        underMaxSupply(_numberToMint)
    {
        for (uint256 i=0; i < _numberToMint; i++) {
            DojoRarity dojoRarity = getDojo(1, 0);
            tokenIdToRarity[totalSupply()] = dojoRarity;

            _mint(msg.sender, totalSupply());
        }
    }

    function ownerMintToAddress(address _address, uint256 _numberToMint)
        external
        onlyOwner
        underMaxSupply(_numberToMint)
    {
        for (uint256 i=0; i < _numberToMint; i++) {
            DojoRarity dojoRarity = getDojo(1, 0);
            tokenIdToRarity[totalSupply()] = dojoRarity;
            
            _mint(_address, totalSupply());
            emit LandRarity(totalSupply()-1, uint8(dojoRarity));
        }
    }

    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function withdrawFunds() external onlyOwner {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

    function setSignatureVerifier(address _signatureVerifier)
        external
        onlyOwner
    {
        signatureVerifier = _signatureVerifier;
    }

    function setClaimPeriodActive() external onlyOwner {
        mintState = MintState.CLAIM_PERIOD;
    }

    function setPostClaimPeriodActive() external onlyOwner {
        mintState = MintState.POST_CLAIM;
    }

    function pauseMint() external onlyOwner {
        mintState = MintState.INACTIVE;
    }

    function setSamuRiseLandMetadataStateContract(address _samuRiseLandMetadataStateContract) external onlyOwner {
        samuRiseLandMetadataStateContract = _samuRiseLandMetadataStateContract;
    }

   function _authorizeUpgrade(address) internal override onlyOwner {}
}

