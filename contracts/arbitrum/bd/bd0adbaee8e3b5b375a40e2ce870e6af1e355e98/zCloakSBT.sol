pragma solidity >=0.8.0 <0.9.0;

//SPDX-License-Identifier: Apache-2.0
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./ERC721Enumerable.sol";
import "./Strings.sol";
import "./Counters.sol";
import {Tokens} from "./Tokens.sol";

error Soulbound();
error MintDisabled();
error TokenNotExist();
error MintInfoInvalid();
error AlreadyMint();
error DigestAlreadyRevoked(bytes32 digest);
error BindingNotExist();
error BindingAlreadyOccupied();
error BindingSignatureInvalid();
error VerifierNotInWhitelist();
error AlreadySetKey();
error NotSetKey();
error VCAlreadyExpired();
error AttesterSignatureInvalid();
error UnBindingLimited();
error OnChainRecipientNotSet();
error TokenNotValid();

contract zCloakSBT is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using Strings for uint256;

    /*///////////////////////////////////////////////////////////////
    STORAGE
    //////////////////////////////////////////////////////////////*/

    Counters.Counter private _tokenIds;

    bool public mintOpen;

    // used for attesters to store their assertionMethod mapping;
    mapping(address => address) private _assertionMethodMapping;

    mapping(address => bool) private _verifierWhitelist;

    mapping(uint256 => Tokens.TokenOnChain) private _tokenDB;

    // used to bind a did address with a eth address (all the sbt mint to the binding addr should be mint to the binded addr instead)
    mapping(address => address) private _bindingDB;

    // Record all tokenIDs send to the binded address
    mapping(address => mapping(address => uint256[])) private _bindedSBT;

    // Record the tokenID mint by the verifier, is the verifier is dishonest, burn all SBTs handled by the verifier
    mapping(address => uint256[]) private _verifierWorkDB;

    // Avoid mint multiple SBT of the same tokenInfo, we need to add a registry to flag that（digest, attester, programHash, publicInputHash, ctype) => tokenID
    // No matter whether the publicInput is defined or not, there always a publicInputHash for that (if the publicInputIsNone, then publicInputHash is keccak as well)
    mapping(bytes32 => mapping(address => mapping(bytes32 => mapping(bytes32 => mapping(bytes32 => uint256)))))
        private _onlyTokenID;

    // A storage for the attester to revoke certain VC, thus the SBT should be burn therefore(if not mint yet, forbid its mint in the future) (attester, digest)
    mapping(address => mapping(bytes32 => bool)) private _revokeDB;

    // Record holder's owned tokenID history
    mapping(address => uint256[]) private _holderTokenHistoryDB;

    // Record token's Verifier
    mapping(uint256 => address) private _tokenVerifier;

    // Check whether the address owns certain SBT, address realRecipient, address attester, bytes32 programHash, bytes32 ctype => Struct { publicInput, tokenID}
    // Only used in two circumstance: 1) the program doesn't have any publicInput, 2) the publicInput is not nesscessary, but can be find via tokenID Info
    mapping(address => mapping(address => mapping(bytes32 => mapping(bytes32 => Tokens.SBTWithUnnecePublicInput))))
        private _certainSbtDB;

    // Check whether the address owns certain SBT, address realRecipient, address attester, bytes32 programHash, publicInputHash, bytes32 ctype => tokenID
    mapping(address => mapping(address => mapping(bytes32 => mapping(bytes32 => mapping(bytes32 => uint256)))))
        private _certainSbtWithPublicInputDB;
    // Record all SBT(tokenID) minted by the specific digest (attester, digest) => tokenID[]
    mapping(address => mapping(bytes32 => uint256[]))
        private _digestConvertCollection;

    /*///////////////////////////////////////////////////////////////
    EVENTS
    //////////////////////////////////////////////////////////////*/

    event MintSuccess(
        uint256 indexed tokenID,
        bytes32 programHash,
        bytes32 digestHash,
        uint64[] publicInput,
        bool isPublicInputUsedForCheck,
        uint64[] output,
        uint64 createdTime,
        uint64 expiredTime,
        address indexed attester,
        address claimer,
        address indexed recipient,
        bytes32 ctypeHash,
        string sbtLink
    );
    event RevokeSuccess(
        address indexed attester,
        bytes32 indexed digestHash,
        uint256[] tokenIDList
    );
    event BindingSetSuccess(
        address indexed bindingAddr,
        address indexed bindedAddr
    );
    event UnBindingSuccess(
        address indexed bindingAddr,
        address indexed bindedAddr
    );
    event VerifierWhiteListAdd(address[] indexed verifiers);
    event VerifierWhiteListDelete(address[] indexed verifiers);
    event VerifierInvalidToken(
        address indexed verifier,
        uint256[] indexed tokenID
    );
    event UserBurnToken(address indexed user, uint256 indexed tokenID);
    event UserUnBindBurn(address indexed user, uint256[] indexed tokenID);
    event AssertionMethodAdd(
        address indexed attester,
        address indexed assertionMethod
    );
    event AssertionMethodRemove(
        address indexed attester,
        address indexed assertionMethod
    );

    /*///////////////////////////////////////////////////////////////
 EIP-712 STORAGE
 //////////////////////////////////////////////////////////////*/

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    /*///////////////////////////////////////////////////////////////
 STRUCTOR
 //////////////////////////////////////////////////////////////*/

    constructor(address[] memory verifiers) ERC721("zCloak SBT", "zk-SBT") {
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = DomainSeparator();
        modifyVerifierWhitelist(true, verifiers);
    }

    /*///////////////////////////////////////////////////////////////
 CORE LOGIC
 //////////////////////////////////////////////////////////////*/

    /**
     * @notice Used to add or delete some verifiers to/from the verifierWhiteList, is `isAdd` is true, add, else remove
     */
    //prettier-ignore
    function modifyVerifierWhitelist(bool isAdd, address[] memory modifiedVerifiers) public onlyOwner {
        if (isAdd){
            for ( uint i = 0; i < modifiedVerifiers.length; i++){
                require(_verifierWhitelist[modifiedVerifiers[i]] == false, "Already in VerifierWhitelist");
                _verifierWhitelist[modifiedVerifiers[i]] = true;
            }
            emit VerifierWhiteListAdd(modifiedVerifiers);
        } else {
            for ( uint i = 0; i < modifiedVerifiers.length; i++){
                require(_verifierWhitelist[modifiedVerifiers[i]] == true, "Not in VerifierWhitelist");
                _verifierWhitelist[modifiedVerifiers[i]] = false;
                for (uint j = 0; j < _verifierWorkDB[modifiedVerifiers[i]].length; j++){
                   if (_exists(_verifierWorkDB[modifiedVerifiers[i]][j])){
                        super._burn(_verifierWorkDB[modifiedVerifiers[i]][j]);
                        delete _tokenDB[_verifierWorkDB[modifiedVerifiers[i]][j]];
                    }    
                }
                emit VerifierInvalidToken(modifiedVerifiers[i], _verifierWorkDB[modifiedVerifiers[i]]);
                _verifierWorkDB[modifiedVerifiers[i]] = new uint256[](0);
            } 
            emit VerifierWhiteListDelete(modifiedVerifiers);

        }
    }

    /**
     * @notice Use to help attester to add/remove assertionMethod
     */
    //prettier-ignore
    function modifyAttesterAssertionMethod(address attester, address assertionMethod, bool isAdd) public onlyOwner {
        if (_assertionMethodMapping[attester] == address(0) && isAdd == true){
            _assertionMethodMapping[attester] = assertionMethod;
            emit AssertionMethodAdd(attester, assertionMethod);
        } else if (_assertionMethodMapping[attester] == address(0) && isAdd == false){
            revert NotSetKey();
        } else if (_assertionMethodMapping[attester] != address(0) && isAdd == true){
            revert AlreadySetKey();
        } else if (_assertionMethodMapping[attester] != address(0) && isAdd == false){
            emit AssertionMethodRemove(attester, _assertionMethodMapping[attester]);
            _assertionMethodMapping[attester] = address(0);
        }
    
    }

    /**
     * @notice Mint a zkSBT according to the TokenInfo and the Signature generated by the ZKP Verifier
     */
    //prettier-ignore
    function mint(Tokens.Token calldata tokenInfo, bytes calldata verifierSignature) public payable nonReentrant {
        if (mintOpen == false) revert MintDisabled();

        if (tokenInfo.expirationTimestamp != 0 && tokenInfo.expirationTimestamp <= _time()){
            revert VCAlreadyExpired();
        }

        if (_bindingDB[tokenInfo.recipient] == address(0)){
            revert OnChainRecipientNotSet();
        }

        // check whether the signature is valid (assertionMethod)
        address attesterAssertionMethod = (_assertionMethodMapping[tokenInfo.attester] == address(0) ? tokenInfo.attester : _assertionMethodMapping[tokenInfo.attester]);
        if (Tokens.verifyAttesterSignature(attesterAssertionMethod, tokenInfo.attesterSignature, tokenInfo.digest, tokenInfo.vcVersion) == false) {
            revert AttesterSignatureInvalid();
        }

        // Make sure the SBT hasn't been mint yet
        bytes32 publicInputHash = keccak256(abi.encodePacked(tokenInfo.publicInput));

        uint256 maybe_mint_id =  _onlyTokenID[tokenInfo.digest][tokenInfo.attester][tokenInfo.programHash][publicInputHash][tokenInfo.ctype];

        if (maybe_mint_id != 0 && checkTokenValid(maybe_mint_id)){
            revert AlreadyMint();
        }

        // Make sure the VC issued by the attester is not revoked yet
        if (_revokeDB[tokenInfo.attester][tokenInfo.digest] == true) {
            revert DigestAlreadyRevoked(tokenInfo.digest);
        }

        // Make sure the verifier is in our WhiteList
        if (_verifierWhitelist[tokenInfo.verifier] == false) {
            revert VerifierNotInWhitelist();
        }

        // Verify the signature first, then mint
        bool isTokenInfoValid = Tokens.verifySignature(tokenInfo, verifierSignature, INITIAL_DOMAIN_SEPARATOR);
        if (isTokenInfoValid == false) revert MintInfoInvalid();

        _tokenIds.increment();
        uint256 id = _tokenIds.current();

        // check whether there exist a binded address on-chain, if yes, mint the SBT to the binded address
        address realRecipient = _bindingDB[tokenInfo.recipient];
        _bindedSBT[Tokens.getRecipient(tokenInfo)][realRecipient].push(id);


        Tokens.TokenOnChain memory tokenOnChainInfo = Tokens.fillTokenOnChain(tokenInfo, _time(), realRecipient);

        _mint(realRecipient, id);
        _tokenDB[id] = tokenOnChainInfo;
        _holderTokenHistoryDB[realRecipient].push(id);
        _tokenVerifier[id] = tokenInfo.verifier; 
        // Push the tokenID to the work of the verifier
        _verifierWorkDB[tokenInfo.verifier].push(id);

        _onlyTokenID[tokenOnChainInfo.digest][tokenOnChainInfo.attester][tokenOnChainInfo.programHash][publicInputHash][tokenOnChainInfo.ctype] = id;

        
        if (tokenInfo.isPublicInputUsedForCheck == false){
            _certainSbtDB[realRecipient][tokenOnChainInfo.attester][tokenOnChainInfo.programHash][tokenOnChainInfo.ctype] = Tokens.SBTWithUnnecePublicInput(tokenInfo.publicInput, id);
        } else {
            _certainSbtWithPublicInputDB[realRecipient][tokenOnChainInfo.attester][tokenOnChainInfo.programHash][publicInputHash][tokenOnChainInfo.ctype] = id;
        }

        // Add the tokenID to the digest collection, when revoke the digest, could burn all the tokenID related to that
        _digestConvertCollection[tokenOnChainInfo.attester][tokenOnChainInfo.digest].push(id);

        emit MintSuccess(id, tokenOnChainInfo.programHash,tokenOnChainInfo.digest, tokenOnChainInfo.publicInput, tokenOnChainInfo.isPublicInputUsedForCheck, tokenOnChainInfo.output, _time(), tokenOnChainInfo.expirationTimestamp, tokenOnChainInfo.attester, tokenInfo.recipient, realRecipient, tokenOnChainInfo.ctype, tokenOnChainInfo.sbtLink);
    }

    /**
     * @notice A function for attesters to register the revoked VC digest, which thus burn the SBT made by the digest, and if not mint yet, forbid its mint in the future
     */
    //prettier-ignore
    function revokeByDigest(bytes32[] calldata digestList) public {
        for (uint j = 0; j < digestList.length; j ++){
            bytes32 digest = digestList[j];
            if (_revokeDB[msg.sender][digest] == true) {
                revert DigestAlreadyRevoked(digest);
            }

            _revokeDB[msg.sender][digest] = true;

            uint256[] memory revokeList = _digestConvertCollection[msg.sender][digest];
            for (uint i = 0; i < revokeList.length; i++){
                if (_exists(revokeList[i])){
                    super._burn(revokeList[i]);
                }
                bytes32 publicInputHash = keccak256(abi.encodePacked(_tokenDB[revokeList[i]].publicInput));
                delete _onlyTokenID[_tokenDB[revokeList[i]].digest][_tokenDB[revokeList[i]].attester][_tokenDB[revokeList[i]].programHash][publicInputHash][_tokenDB[revokeList[i]].ctype];
                if (_tokenDB[revokeList[i]].isPublicInputUsedForCheck == false){
                    delete _certainSbtDB[_tokenDB[revokeList[i]].recipient][_tokenDB[revokeList[i]].attester][_tokenDB[revokeList[i]].programHash][_tokenDB[revokeList[i]].ctype];
                }else{
                    delete _certainSbtWithPublicInputDB[_tokenDB[revokeList[i]].recipient][_tokenDB[revokeList[i]].attester][_tokenDB[revokeList[i]].programHash][publicInputHash][_tokenDB[revokeList[i]].ctype];
                }
                delete _tokenDB[revokeList[i]];
            }
            emit RevokeSuccess(msg.sender, digest, revokeList);
        }
    }

    /**
     * @notice Used to set the binding relation, the `signatureBinding` should be generated by the bindingAddr, the `signatureBinded` should be generated by the bindedAddr
     */
    //prettier-ignore
    // eip 191 -- I bound oxabcd to 0x1234.
    function setBinding(address bindingAddr, address bindedAddr, bytes calldata bindingSignature, bytes calldata bindedSignature) public payable {
        if (_bindingDB[bindingAddr] != address(0)) {
            revert BindingAlreadyOccupied();
        }
        if (Tokens.verifyBindingSignature(bindingAddr, bindedAddr, bindingSignature, bindedSignature) == true) {
            _bindingDB[bindingAddr] = bindedAddr;
            emit BindingSetSuccess(bindingAddr, bindedAddr);
        } else {
            revert BindingSignatureInvalid();
        }
    }

    /**
     * @notice Used to set the unbind the ralation stored on chain
     */
    //prettier-ignore
    function unBinding(address bindingAddr, address bindedAddr) public payable {
        if (_bindingDB[bindingAddr] != bindedAddr) {
            revert BindingNotExist();
        }
        if (msg.sender == bindingAddr || msg.sender == bindedAddr) {
            // revoke all related SBT
            uint256[] memory revokeList = _bindedSBT[bindingAddr][bindedAddr];
            for (uint i = 0; i < revokeList.length; i++){
                if (_exists(revokeList[i])){
                    super._burn(revokeList[i]);
                } 
                bytes32 publicInputHash = keccak256(abi.encodePacked(_tokenDB[revokeList[i]].publicInput));
                delete _onlyTokenID[_tokenDB[revokeList[i]].digest][_tokenDB[revokeList[i]].attester][_tokenDB[revokeList[i]].programHash][publicInputHash][_tokenDB[revokeList[i]].ctype];
                if (_tokenDB[revokeList[i]].isPublicInputUsedForCheck == false){
                    delete _certainSbtDB[_tokenDB[revokeList[i]].recipient][_tokenDB[revokeList[i]].attester][_tokenDB[revokeList[i]].programHash][_tokenDB[revokeList[i]].ctype];
                } else {
                    delete _certainSbtWithPublicInputDB[_tokenDB[revokeList[i]].recipient][_tokenDB[revokeList[i]].attester][_tokenDB[revokeList[i]].programHash][publicInputHash][_tokenDB[revokeList[i]].ctype];
                }
                delete _tokenDB[revokeList[i]];
            }
            // set it to default
            delete _bindingDB[bindingAddr];
            delete _bindedSBT[bindingAddr][bindedAddr];
            if (revokeList.length != 0){
                emit UserUnBindBurn(bindingAddr, revokeList);
            }
            emit UnBindingSuccess(bindingAddr, bindedAddr);
        } else {
            revert UnBindingLimited();
        }
    }

    /**
     * @notice Used to set the key ralation stored on chain. Eth => assertionMethod
     */
    //prettier-ignore
    function setAssertionMethod(address assertionMethod) public payable {
        if (_assertionMethodMapping[msg.sender] != address(0)) {
            revert AlreadySetKey();
        }
        _assertionMethodMapping[msg.sender] = assertionMethod;
        emit AssertionMethodAdd(msg.sender, assertionMethod);
    }

    /**
     * @notice Used to remove the key ralation stored on chain
     */
    //prettier-ignore
    function removeAssertionMethod() public payable {
        if (_assertionMethodMapping[msg.sender] == address(0)) {
            revert NotSetKey();
        }
        emit AssertionMethodRemove(msg.sender, _assertionMethodMapping[msg.sender]);
        _assertionMethodMapping[msg.sender] = address(0);
    }

    function checkAssertionMethod(
        address addressToCheck
    ) public view returns (address) {
        return _assertionMethodMapping[addressToCheck];
    }

    /**
     * @notice Used to check whether the user owns a certain class of zkSBT with certain programHash, and whether it is valid at present.
     * If the publicInput is provided, then check the program with publicInput, else not
     */
    //prettier-ignore
    function checkSBTClassValid(address userAddr, address attester, bytes32 programHash, uint64[] calldata publicInput, bytes32 ctype) public view returns (Tokens.TokenOnChain memory) {
        uint256 tokenID;
        if (publicInput.length == 0){
             tokenID = _certainSbtDB[userAddr][attester][programHash][ctype].tokenID;
        } else {
            bytes32 publicInputHash = keccak256(abi.encodePacked(publicInput));
            tokenID = _certainSbtWithPublicInputDB[userAddr][attester][programHash][publicInputHash][ctype];
        }
       
        if (!checkTokenValid(tokenID)){
            revert TokenNotValid();
        }
        
        return _tokenDB[tokenID];
    }

    /**
     * @notice Check whether a zkSBT is valid, check its existance, expirationDate not reach and it hasn't been revoked.
     * add verifier list.
     */
    //prettier-ignore
    function checkTokenValid(uint256 id) public view returns (bool) {
        // check its existance
        // todo: do a test -- check if an attester revoked, wheather it is still exsit?
        if (!_exists(id)) return false;

        // check its expirationDate
        if (_tokenDB[id].expirationTimestamp != 0 && _tokenDB[id].expirationTimestamp <= _time()){
            return false;
        }
        return true;
    }

    /**
     * @notice Receives json from constructTokenURI
     */
    // prettier-ignore
    function tokenURI(uint256 id) public view override returns (string memory) {
        if (!_exists(id)) revert TokenNotExist();
        string memory sbtImage = _tokenDB[id].sbtLink;
        return string.concat('{"name": "zk-SBT #', id.toString(),'","image":"', sbtImage, '"}');
    }

    function contractURI() external pure returns (string memory) {
        string
            memory collectionImage = "https://arweave.net/7kij1nQzLRYAr81vDF3szWkQj-tzhwuw-QzVAUJwxPg";
        string memory json = string.concat(
            '{"name": "zCloak SBT","description":"This is a zkSBT collection launched by zCloak Network which can be used to represent ones personal identity without revealing their confidential information","image":"',
            collectionImage,
            '"}'
        );
        return string.concat("data:application/json;utf8,", json);
    }

    /**
     * @notice Toggles Pledging On / Off
     */
    function toggleMinting() public onlyOwner {
        mintOpen == false ? mintOpen = true : mintOpen = false;
    }

    /*///////////////////////////////////////////////////////////////
    TOKEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice SOULBOUND: Block transfers.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override(ERC721Enumerable) {
        require(
            // can only be mint by address `0` and can be (burn by) transfered to the opensea burn address
            from == address(0) ||
                to == address(0x000000000000000000000000000000000000dEaD) ||
                to == address(0x0000000000000000000000000000000000000000),
            "SOULBOUND: Non-Transferable"
        );
        require(batchSize == 1, "Can only mint/burn one at the same time");
        if (
            to == address(0x000000000000000000000000000000000000dEaD) ||
            to == address(0x0000000000000000000000000000000000000000)
        ) {
            if (msg.sender == _tokenDB[firstTokenId].recipient) {
                emit UserBurnToken(msg.sender, firstTokenId);
            }
            bytes32 publicInputHash = keccak256(
                abi.encodePacked(_tokenDB[firstTokenId].publicInput)
            );
            delete _onlyTokenID[_tokenDB[firstTokenId].digest][
                _tokenDB[firstTokenId].attester
            ][_tokenDB[firstTokenId].programHash][publicInputHash][
                _tokenDB[firstTokenId].ctype
            ];
            if (_tokenDB[firstTokenId].isPublicInputUsedForCheck == false) {
                delete _certainSbtDB[_tokenDB[firstTokenId].recipient][
                    _tokenDB[firstTokenId].attester
                ][_tokenDB[firstTokenId].programHash][
                    _tokenDB[firstTokenId].ctype
                ];
            } else {
                delete _certainSbtWithPublicInputDB[
                    _tokenDB[firstTokenId].recipient
                ][_tokenDB[firstTokenId].attester][
                    _tokenDB[firstTokenId].programHash
                ][publicInputHash][_tokenDB[firstTokenId].ctype];
            }

            delete _tokenDB[firstTokenId];
        }
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    /**
     * @notice SOULBOUND: Block approvals.
     */
    function setApprovalForAll(
        address operator,
        bool _approved
    ) public virtual override(ERC721, IERC721) {
        revert Soulbound();
    }

    /**
     * @notice SOULBOUND: Block approvals.
     */
    function approve(
        address to,
        uint256 tokenId
    ) public virtual override(ERC721, IERC721) {
        revert Soulbound();
    }

    function CHAIN_ID() public view virtual returns (uint256) {
        return INITIAL_CHAIN_ID;
    }

    function DomainSeparator() public view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes("zCloakSBT")),
                    keccak256(bytes("0")),
                    block.chainid,
                    address(this)
                )
            );
    }

    /**
     * @dev Returns the current's block timestamp. This method is overridden during tests and used to simulate the
     * current block time.
     */
    function _time() internal view returns (uint64) {
        // return the milsec of the current timestamp
        return uint64(block.timestamp) * 1000;
    }

    /////////////// TEST FUNCTIONS ///////////////
    function checkVerifierWhitelist(
        address verifier
    ) public view returns (bool) {
        return _verifierWhitelist[verifier];
    }

    function checkTokenInfo(
        uint256 tokenID
    ) public view returns (Tokens.TokenOnChain memory) {
        return _tokenDB[tokenID];
    }

    function checkRevokeDB(
        address attester,
        bytes32 digest
    ) public view returns (bool) {
        return _revokeDB[attester][digest];
    }

    function checkDigestConvertCollection(
        address attester,
        bytes32 digest
    ) public view returns (uint256[] memory) {
        return _digestConvertCollection[attester][digest];
    }

    function checkBindingDB(address bindingAddr) public view returns (address) {
        return _bindingDB[bindingAddr];
    }

    // function checkBindingSBTDB(
    //     address bindingAddr
    // ) public view returns (uint256[] memory) {
    //     return _bindedSBT[bindingAddr][_bindingDB[bindingAddr]];
    // }

    // function checkVerifierWorkDB(
    //     address verifier
    // ) public view returns (uint256[] memory) {
    //     return _verifierWorkDB[verifier];
    // }

    function checkTokenExist(uint256 tokenID) public view returns (bool) {
        return _exists(tokenID);
    }

    function checkOnlyTokenID(
        bytes32 digest,
        address attester,
        bytes32 programHash,
        uint64[] calldata publicInput,
        bytes32 ctype
    ) public view returns (uint256) {
        bytes32 publicInputHash = keccak256(abi.encodePacked(publicInput));
        return
            _onlyTokenID[digest][attester][programHash][publicInputHash][ctype];
    }
}

