// SPDX-License-Identifier: MIT
// Powered by: Origamasks

pragma solidity ^0.8.7;

import "./ERC721A.sol";
import "./Ownable.sol";
import "./ERC2981.sol";
import "./Counters.sol";
import "./ECDSA.sol";
import "./VRFV2WrapperConsumerBase.sol";

error IncorrectPrice();
error NotUser();
error InvalidSaleState();
error ZeroAddress();
error LimitPerTxnExceeded();
error SoldOut();
error InvalidSignature();
error ProvenanceHashNotSetYet();
error StartingIndexExisted();

contract TheBirdsOfEmotion is
    ERC721A,
    Ownable,
    ERC2981,
    VRFV2WrapperConsumerBase
{
    /* SUPPLY */
    uint256 public constant LIMIT_PER_TXN = 10;
    uint256 public collectionSize = 365;
    uint256 public mintPrice = 0.008 ether;
    uint256 public publicMintPrice = 0.05 ether;
    string private baseTokenURI;
    string private contractMetadataURI;

    /* PROVENANCE HASH */
    string public provenanceHash;
    uint256 public startingIndex;

    /* SIGNATURE */
    using ECDSA for bytes32;
    address public signerAddress;

    // EVENT
    event Minted(address indexed receiver, uint256 quantity);

    constructor(
        address signer_,
        address payable withdrawAddress_,
        address linkAddress_,
        address wrapperAddress_,
        string memory defaultPreRevealBaseURI_,
        string memory contractURI_
    )
        ERC721A("TheBirdsOfEmotion", "TheBirdsOfEmotion")
        VRFV2WrapperConsumerBase(linkAddress_, wrapperAddress_)
    {
        setSignerAddress(signer_);
        setWithdrawAddress(withdrawAddress_);
        setRoyaltyInfo(1000); //(1000 → 10%);
        setBaseTokenURI(defaultPreRevealBaseURI_);
        setContractMetadataURI(contractURI_);
    }

    /* SALE STATE */
    enum SaleState {
        Closed,
        Public
    }
    SaleState public saleState;
    event SaleStateChanged(SaleState saleState);
    modifier isSaleState(SaleState saleState_) {
        if (msg.sender != tx.origin) revert NotUser();
        if (saleState != saleState_) revert InvalidSaleState();
        _;
    }

    /* MINT */
    function publicMint(uint256 quantity_, bytes calldata signature_)
        external
        payable
        isSaleState(SaleState.Public)
    {
        if (!verifySignature(signature_, "Public")) revert InvalidSignature();
        if (msg.value != quantity_ * mintPrice) revert IncorrectPrice();
        if (quantity_ > LIMIT_PER_TXN) revert LimitPerTxnExceeded();
        if (_totalMinted() + quantity_ > collectionSize) revert SoldOut();

        _mint(msg.sender, quantity_);
        emit Minted(msg.sender, quantity_);
    }

    function verifySignature(
        bytes memory signature_,
        string memory saleStateName_
    ) internal view returns (bool) {
        return
            signerAddress ==
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    bytes32(abi.encodePacked(msg.sender, saleStateName_))
                )
            ).recover(signature_);
    }

    function numberMinted(address account) external view returns (uint256) {
        return _numberMinted(account);
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function contractURI() public view returns (string memory) {
        return contractMetadataURI;
    }

    /* ONLY OWNER */

    /*
    // @notice Function used to change the current `saleState` value. 
    */
    function setSaleState(uint256 saleState_) external onlyOwner {
        if (saleState_ > uint256(SaleState.Public)) revert InvalidSaleState();

        saleState = SaleState(saleState_);
        emit SaleStateChanged(saleState);
    }

    /**
     * @dev set the provenance hash (if more than once -> for emergency only if art needs to be fixed, not affecting order / rarity)
     */
    function setProvenanceHash(string memory provenanceHash_)
        external
        onlyOwner
    {
        provenanceHash = provenanceHash_;
    }

    function setSignerAddress(address signerAddress_) public onlyOwner {
        if (signerAddress_ == address(0)) revert ZeroAddress();
        signerAddress = signerAddress_;
    }

    function setBaseTokenURI(string memory baseTokenURI_) public onlyOwner {
        baseTokenURI = baseTokenURI_;
    }

    function setContractMetadataURI(string memory contractMetadataURI_)
        public
        onlyOwner
    {
        contractMetadataURI = contractMetadataURI_;
    }

    /* WITHDRAW */
    // Sets Withdraw Address for withdraw() and ERC2981 royaltyInfo
    address payable public withdrawAddress;

    /**
     * @dev withdraw function for owner.
     */
    function withdraw() external onlyOwner {
        (bool success, ) = withdrawAddress.call{value: address(this).balance}(
            ""
        );
        require(success, "Transfer failed.");
    }

    /**
     * Allow withdraw of Link tokens from the contract
     */
    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(linkAddress);
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }

    /**
     * @dev Update the royalty wallet address
     */
    function setWithdrawAddress(
        address payable withdrawAddress_
    ) public onlyOwner {
        if (withdrawAddress_ == address(0)) revert ZeroAddress();
        withdrawAddress = withdrawAddress_;
    }

    /**
     * ROYALTY
     * @dev Update the royalty percentage (500 = 5%)
     */
    function setRoyaltyInfo(uint96 royaltyPercentage_) public onlyOwner {
        if (withdrawAddress == address(0)) revert ZeroAddress();
        _setDefaultRoyalty(withdrawAddress, royaltyPercentage_);
    }

    /**
     * OVERRIDE
     * @dev {ERC165-supportsInterface} Adding IERC2981
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721A, ERC2981)
        returns (bool)
    {
        return
            ERC2981.supportsInterface(interfaceId) ||
            super.supportsInterface(interfaceId);
    }

    /* CHAINLINK FOR RANDOM */
    /* BEGIN CHAINLINK CONFIG */

    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(
        uint256 requestId,
        uint256[] randomWords,
        uint256 payment
    );

    struct RequestStatus {
        uint256 paid; // amount paid in link
        bool fulfilled; // whether the request has been successfully fulfilled
        uint256[] randomWords;
    }
    mapping(uint256 => RequestStatus) public s_requests; /* requestId --> requestStatus */

    // past requests Id.
    uint256[] public requestIds;
    uint256 public lastRequestId;

    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    uint32 callbackGasLimit = 100000;

    // The default is 3, but you can set this higher.
    uint16 requestConfirmations = 3;

    // For this example, retrieve 2 random values in one request.
    // Cannot exceed VRFV2Wrapper.getConfig().maxNumWords.
    uint32 numWords = 1;

    // Address LINK - hardcoded for Goerli
    address public linkAddress;

    /* END CHAINLINK CONFIG */

    // Assumes the subscription is funded sufficiently.
    function requestRandomStartingIndex()
        external
        onlyOwner
        returns (uint256 requestId)
    {
        if (bytes(provenanceHash).length <= 0) revert ProvenanceHashNotSetYet();
        if (startingIndex > 0) revert StartingIndexExisted();

        requestId = requestRandomness(
            callbackGasLimit,
            requestConfirmations,
            numWords
        );
        s_requests[requestId] = RequestStatus({
            paid: VRF_V2_WRAPPER.calculateRequestPrice(callbackGasLimit),
            randomWords: new uint256[](0),
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        return requestId;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].paid > 0, "request not found");
        s_requests[_requestId].fulfilled = true;
        // s_requests[_requestId].randomWords = _randomWords;

        startingIndex = _randomWords[0] % collectionSize;
        // Prevent default sequence
        if (startingIndex == 0) {
            startingIndex = startingIndex + 1;
        }

        emit RequestFulfilled(
            _requestId,
            _randomWords,
            s_requests[_requestId].paid
        );
    }

    function getRequestStatus(uint256 _requestId)
        external
        view
        returns (
            uint256 paid,
            bool fulfilled,
            uint256[] memory randomWords
        )
    {
        require(s_requests[_requestId].paid > 0, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.paid, request.fulfilled, request.randomWords);
    }

    /**
     * Useful for unit tests. Not to use in production.
     */

    function setCollectionSize(uint256 size) public onlyOwner {
        collectionSize = size;
    }
}

