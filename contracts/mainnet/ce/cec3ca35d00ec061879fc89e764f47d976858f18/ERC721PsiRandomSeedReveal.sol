// SPDX-License-Identifier: MIT
/**
  ______ _____   _____ ______ ___  __ _  _  _ 
 |  ____|  __ \ / ____|____  |__ \/_ | || || |
 | |__  | |__) | |        / /   ) || | \| |/ |
 |  __| |  _  /| |       / /   / / | |\_   _/ 
 | |____| | \ \| |____  / /   / /_ | |  | |   
 |______|_|  \_\\_____|/_/   |____||_|  |_|   
                                              
                                            
 */
pragma solidity ^0.8.0;

import "./VRFCoordinatorV2Interface.sol";
import "./VRFConsumerBaseV2.sol";
import "./ERC721Psi.sol";

import "./IERC721RandomSeed.sol";

abstract contract ERC721PsiRandomSeedReveal is ERC721Psi, IERC721RandomSeed, VRFConsumerBaseV2 {
    // Chainklink VRF V2
    VRFCoordinatorV2Interface immutable COORDINATOR;
    uint32 immutable callbackGasLimit;
    uint16 immutable requestConfirmations;
    uint16 constant numWords = 1;
    
    // requestId => genId
    mapping(uint256 => uint256) private requestIdToGenId;
    
    // genId => seed
    mapping(uint256 => uint256) private genSeed;

    // genId => tokenId threshold
    mapping(uint256 => uint256) private genThreshold;

    // current genId for minting
    uint256 private currentGen;

    event RandomnessRequest(uint256 requestId);
    
    constructor(
        address coordinator,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations
    ) VRFConsumerBaseV2(coordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(coordinator);
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 randomness = randomWords[0];
        uint256 genId = requestIdToGenId[requestId];
        delete requestIdToGenId[genId];
        genSeed[genId] = randomness;
        _processRandomnessFulfillment(requestId, genId, randomness);
    }

    /**
        @dev Request the randomess for the tokens of the current generation.
     */
    function _reveal() internal virtual {
        uint256 requestId = COORDINATOR.requestRandomWords(
            _keyHash(),
            _subscriptionId(),
            requestConfirmations,
            callbackGasLimit,
            numWords
        );

        emit RandomnessRequest(requestId);
        requestIdToGenId[requestId] = currentGen;
        _processRandomnessRequest(requestId, currentGen);
        genThreshold[currentGen] = _minted;
        currentGen++;
    }

    /**
        @dev Query the generation of `tokenId`.
     */
    function _tokenGen(uint256 tokenId) internal view returns (uint256) {
        // Find the generation the tokenId belongs to by checking it against genThreshold
        for (uint256 i = 0; i < currentGen; ++i) {
            if (tokenId < genThreshold[i]) {
                return i;
            }
        }
        return currentGen;
    }

    /**
        @dev Return the random seed of `tokenId`.

        Revert when the randomness hasn't been fulfilled.
     */
    function seed(uint256 tokenId) public virtual override view returns (uint256){
        require(_exists(tokenId), "ERC721PsiRandomSeedReveal: seed query for nonexistent token");
        
        unchecked {
            uint256 _genSeed = genSeed[_tokenGen(tokenId)];
            require(_genSeed != 0, "ERC721PsiRandomSeedReveal: Randomness hasn't been fullfilled");
            return uint256(keccak256(
                abi.encode(_genSeed, tokenId)
            ));
        }
    }

    /**
        @dev Return the random seed of `tokenId` with extra nonce.

        Revert when the randomness hasn't been fulfilled.
    */
    function seedWithNonce(uint256 tokenId, uint256 nonce) public virtual view returns (uint256){
        require(_exists(tokenId), "ERC721PsiRandomSeedReveal: seed query for nonexistent token");
        
        unchecked {
            uint256 _genSeed = genSeed[_tokenGen(tokenId)];
            require(_genSeed != 0, "ERC721PsiRandomSeedReveal: Randomness hasn't been fullfilled");
            return uint256(keccak256(
                abi.encode(_genSeed, tokenId, nonce)
            ));
        }
    }

    /** 
        @dev Override the function to provide the corrosponding keyHash for the Chainlink VRF V2.

        see also: https://docs.chain.link/docs/vrf-contracts/
     */
    function _keyHash() internal virtual returns (bytes32); 
    
    /** 
        @dev Override the function to provide the corrosponding subscription id for the Chainlink VRF V2.

        see also: https://docs.chain.link/docs/get-a-random-number/#create-and-fund-a-subscription
     */
    function _subscriptionId() internal virtual returns (uint64);

    function _processRandomnessRequest(uint256 requestId, uint256 genId) internal {

    }

    function _processRandomnessFulfillment(uint256 requestId, uint256 genId, uint256 randomness) internal {

    }
}
