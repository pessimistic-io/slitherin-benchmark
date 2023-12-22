// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "./ECDSA.sol";
import "./ERC721A.sol";
import "./ERC721AQueryable.sol";
import "./ERC4907A.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";
import "./ERC2981.sol";
import "./RevokableOperatorFilterer.sol";

/**
 * @author Created with HeyMint Launchpad https://launchpad.heymint.xyz
 * @notice This contract handles minting Curious Addys Trading Club tokens.
 */
contract CuriousAddysTradingClub is
    ERC721A,
    ERC721AQueryable,
    ERC4907A,
    Ownable,
    Pausable,
    ReentrancyGuard,
    ERC2981,
    RevokableOperatorFilterer
{
    using ECDSA for bytes32;
    event Stake(uint256 indexed tokenId);
    event Unstake(uint256 indexed tokenId);
    event Loan(address from, address to, uint256 tokenId);
    event LoanRetrieved(address from, address to, uint256 tokenId);

    // Address where burnt tokens are sent
    address burnAddress = 0x000000000000000000000000000000000000dEaD;
    // Default address to subscribe to for determining blocklisted exchanges
    address constant DEFAULT_SUBSCRIPTION =
        address(0x511af84166215d528ABf8bA6437ec4BEcF31934B);
    // Used to validate authorized presale mint addresses
    address private presaleSignerAddress =
        0xD5b4F7Dd8F0BeBE6A866DBEFd37143756DB642C0;
    address public burnToMintContractAddress =
        0x7A4dF7B461f1bE3e88373a4d933aeefE2FAdcE71;
    address public freeClaimContractAddress =
        0x7A4dF7B461f1bE3e88373a4d933aeefE2FAdcE71;
    // Address where HeyMint fees are sent
    address public heymintPayoutAddress =
        0x52EA5F96f004d174470901Ba3F1984D349f0D3eF;
    address public royaltyAddress = 0x7A4dF7B461f1bE3e88373a4d933aeefE2FAdcE71;
    // Used to allow transferring soulbound tokens with admin privileges
    address public soulboundAdminAddress =
        0xD3371FD388664Bd16A267788dbE977582B850f5b;
    address[] public payoutAddresses = [
        0x7A4dF7B461f1bE3e88373a4d933aeefE2FAdcE71
    ];
    // Used to allow an admin to transfer soulbound tokens when necessary
    bool private soulboundAdminTransferInProgress;
    // If true tokens can be burned in order to mint
    bool public burnClaimActive;
    bool public freeClaimActive;
    bool public isPresaleActive;
    bool public isPublicSaleActive;
    // When false, tokens cannot be staked but can still be unstaked
    bool public isStakingActive = true;
    // If false, new loans will be disabled but existing loans can be closed
    bool public loaningActive;
    // Permanently freezes metadata so it can never be changed
    bool public metadataFrozen;
    // If true, payout addresses and basis points are permanently frozen and can never be updated
    bool public payoutAddressesFrozen;
    // If true the soulbind admin address is permanently disabled
    bool public soulbindAdminAddressPermanentlyDisabled;
    bool public stakingTransferActive;
    // If true, tokens can be transferred, if false, tokens are soulbound
    bool public transfersEnabled;
    mapping(address => uint256) public totalLoanedPerAddress;
    mapping(uint256 => address) public tokenOwnersOnLoan;
    // If true token has already been used to claim and cannot be used again
    mapping(uint256 => bool) public freeClaimUsed;
    // Stores a random hash for each token ID
    mapping(uint256 => bytes32) public randomHashStore;
    // Returns the UNIX timestamp at which a token began staking if currently staked
    mapping(uint256 => uint256) public currentTimeStaked;
    // Returns the total time a token has been staked in seconds, not counting the current staking time if any
    mapping(uint256 => uint256) public totalTimeStaked;
    string public baseTokenURI =
        "ipfs://bafybeifx7dlxryntnwj5vzbaf3ofbxwzbliwrhtyqfhmfqv65nzq3aavwu/";
    uint256 private currentLoanIndex = 0;
    // Maximum supply of tokens that can be minted
    uint256 public MAX_SUPPLY = 1000;
    // Total number of tokens available for minting in the presale
    uint256 public PRESALE_MAX_SUPPLY = 500;
    // Fee paid to HeyMint per NFT minted
    uint256 public constant heymintFeePerToken = 0.0007 ether;
    uint256 public mintsPerBurn = 1;
    uint256 public mintsPerClaim = 1;
    uint256 public presaleMintsAllowedPerAddress = 5;
    uint256 public presaleMintsAllowedPerTransaction = 1000;
    uint256 public presalePrice = 0.01 ether;
    uint256 public publicMintsAllowedPerAddress = 3;
    uint256 public publicMintsAllowedPerTransaction = 1000;
    uint256 public publicPrice = 0.012 ether;
    // The respective share of funds to be sent to each address in payoutAddresses in basis points
    uint256[] public payoutBasisPoints = [10000];
    uint96 public royaltyFee = 500;

    constructor()
        ERC721A("Curious Addys Trading Club", "CATC")
        RevokableOperatorFilterer(
            0x000000000000AAeB6D7670E522A718067333cd4E,
            DEFAULT_SUBSCRIPTION,
            true
        )
    {
        _setDefaultRoyalty(royaltyAddress, royaltyFee);
        require(
            payoutAddresses.length == payoutBasisPoints.length,
            "PAYOUT_ARRAYS_NOT_SAME_LENGTH"
        );
        uint256 totalPayoutBasisPoints = 0;
        for (uint256 i = 0; i < payoutBasisPoints.length; i++) {
            totalPayoutBasisPoints += payoutBasisPoints[i];
        }
        require(
            totalPayoutBasisPoints == 10000,
            "TOTAL_BASIS_POINTS_MUST_BE_10000"
        );
    }

    modifier originalUser() {
        require(tx.origin == msg.sender, "CANNOT_CALL_FROM_CONTRACT");
        _;
    }

    /**
     * @dev Used to directly approve a token for transfers by the current msg.sender,
     * bypassing the typical checks around msg.sender being the owner of a given token
     * from https://github.com/chiru-labs/ERC721A/issues/395#issuecomment-1198737521
     */
    function _directApproveMsgSenderFor(uint256 tokenId) internal {
        assembly {
            mstore(0x00, tokenId)
            mstore(0x20, 6) // '_tokenApprovals' is at slot 6.
            sstore(keccak256(0x00, 0x40), caller())
        }
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    /**
     * @dev Overrides the default ERC721A _startTokenId() so tokens begin at 1 instead of 0
     */
    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    /**
     * @notice Change the royalty fee for the collection
     */
    function setRoyaltyFee(uint96 _feeNumerator) external onlyOwner {
        royaltyFee = _feeNumerator;
        _setDefaultRoyalty(royaltyAddress, royaltyFee);
    }

    /**
     * @notice Change the royalty address where royalty payouts are sent
     */
    function setRoyaltyAddress(address _royaltyAddress) external onlyOwner {
        royaltyAddress = _royaltyAddress;
        _setDefaultRoyalty(royaltyAddress, royaltyFee);
    }

    /**
     * @notice Wraps and exposes publicly _numberMinted() from ERC721A
     */
    function numberMinted(address _owner) public view returns (uint256) {
        return _numberMinted(_owner);
    }

    /**
     * @notice Update the base token URI
     */
    function setBaseURI(string calldata _newBaseURI) external onlyOwner {
        require(!metadataFrozen, "METADATA_HAS_BEEN_FROZEN");
        baseTokenURI = _newBaseURI;
    }

    /**
     * @notice Reduce the max supply of tokens
     * @param _newMaxSupply The new maximum supply of tokens available to mint
     */
    function reduceMaxSupply(uint256 _newMaxSupply) external onlyOwner {
        require(_newMaxSupply < MAX_SUPPLY, "NEW_MAX_SUPPLY_TOO_HIGH");
        require(
            _newMaxSupply >= totalSupply(),
            "SUPPLY_LOWER_THAN_MINTED_TOKENS"
        );
        MAX_SUPPLY = _newMaxSupply;
    }

    /**
     * @notice Freeze metadata so it can never be changed again
     */
    function freezeMetadata() external onlyOwner {
        require(!metadataFrozen, "METADATA_HAS_ALREADY_BEEN_FROZEN");
        metadataFrozen = true;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // https://chiru-labs.github.io/ERC721A/#/migration?id=supportsinterface
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721A, IERC721A, ERC2981, ERC4907A)
        returns (bool)
    {
        // Supports the following interfaceIds:
        // - IERC165: 0x01ffc9a7
        // - IERC721: 0x80ac58cd
        // - IERC721Metadata: 0x5b5e139f
        // - IERC2981: 0x2a55205a
        // - IERC4907: 0xad092b5c
        return
            ERC721A.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId) ||
            ERC4907A.supportsInterface(interfaceId);
    }

    /**
     * @notice Allow owner to send 'mintNumber' tokens without cost to multiple addresses
     */
    function gift(address[] calldata receivers, uint256[] calldata mintNumber)
        external
        onlyOwner
    {
        require(
            receivers.length == mintNumber.length,
            "ARRAYS_MUST_BE_SAME_LENGTH"
        );
        uint256 totalMint = 0;
        for (uint256 i = 0; i < mintNumber.length; i++) {
            totalMint += mintNumber[i];
        }
        require(totalSupply() + totalMint <= MAX_SUPPLY, "MINT_TOO_LARGE");
        for (uint256 i = 0; i < receivers.length; i++) {
            _safeMint(receivers[i], mintNumber[i]);
        }
    }

    /**
     * @notice To be updated by contract owner to allow public sale minting
     */
    function setPublicSaleState(bool _saleActiveState) external onlyOwner {
        require(
            isPublicSaleActive != _saleActiveState,
            "NEW_STATE_IDENTICAL_TO_OLD_STATE"
        );
        isPublicSaleActive = _saleActiveState;
    }

    /**
     * @notice Update the public mint price
     */
    function setPublicPrice(uint256 _publicPrice) external onlyOwner {
        publicPrice = _publicPrice;
    }

    /**
     * @notice Set the maximum mints allowed per a given address in the public sale
     */
    function setPublicMintsAllowedPerAddress(uint256 _mintsAllowed)
        external
        onlyOwner
    {
        publicMintsAllowedPerAddress = _mintsAllowed;
    }

    /**
     * @notice Set the maximum public mints allowed per a given transaction
     */
    function setPublicMintsAllowedPerTransaction(uint256 _mintsAllowed)
        external
        onlyOwner
    {
        publicMintsAllowedPerTransaction = _mintsAllowed;
    }

    /**
     * @notice Allow for public minting of tokens
     */
    function mint(uint256 numTokens)
        external
        payable
        nonReentrant
        originalUser
    {
        require(isPublicSaleActive, "PUBLIC_SALE_IS_NOT_ACTIVE");

        require(
            numTokens <= publicMintsAllowedPerTransaction,
            "MAX_MINTS_PER_TX_EXCEEDED"
        );
        require(
            _numberMinted(msg.sender) + numTokens <=
                publicMintsAllowedPerAddress,
            "MAX_MINTS_EXCEEDED"
        );
        require(totalSupply() + numTokens <= MAX_SUPPLY, "MAX_SUPPLY_EXCEEDED");
        uint256 heymintFee = numTokens * heymintFeePerToken;
        require(
            msg.value == publicPrice * numTokens + heymintFee,
            "PAYMENT_INCORRECT"
        );

        (bool success, ) = heymintPayoutAddress.call{value: heymintFee}("");
        require(success, "Transfer failed.");
        _safeMint(msg.sender, numTokens);

        if (totalSupply() >= MAX_SUPPLY) {
            isPublicSaleActive = false;
        }
    }

    /**
     * @notice To be updated by contract owner to allow presale minting
     */
    function setPresaleState(bool _saleActiveState) external onlyOwner {
        require(
            isPresaleActive != _saleActiveState,
            "NEW_STATE_IDENTICAL_TO_OLD_STATE"
        );
        isPresaleActive = _saleActiveState;
    }

    /**
     * @notice Update the presale mint price
     */
    function setPresalePrice(uint256 _presalePrice) external onlyOwner {
        presalePrice = _presalePrice;
    }

    /**
     * @notice Set the maximum mints allowed per a given address in the presale
     */
    function setPresaleMintsAllowedPerAddress(uint256 _mintsAllowed)
        external
        onlyOwner
    {
        presaleMintsAllowedPerAddress = _mintsAllowed;
    }

    /**
     * @notice Set the maximum presale mints allowed per a given transaction
     */
    function setPresaleMintsAllowedPerTransaction(uint256 _mintsAllowed)
        external
        onlyOwner
    {
        presaleMintsAllowedPerTransaction = _mintsAllowed;
    }

    /**
     * @notice Reduce the max supply of tokens available to mint in the presale
     * @param _newPresaleMaxSupply The new maximum supply of presale tokens available to mint
     */
    function reducePresaleMaxSupply(uint256 _newPresaleMaxSupply)
        external
        onlyOwner
    {
        require(
            _newPresaleMaxSupply < PRESALE_MAX_SUPPLY,
            "NEW_MAX_SUPPLY_TOO_HIGH"
        );
        PRESALE_MAX_SUPPLY = _newPresaleMaxSupply;
    }

    /**
     * @notice Set the signer address used to verify presale minting
     */
    function setPresaleSignerAddress(address _presaleSignerAddress)
        external
        onlyOwner
    {
        require(_presaleSignerAddress != address(0));
        presaleSignerAddress = _presaleSignerAddress;
    }

    /**
     * @notice Verify that a signed message is validly signed by the presaleSignerAddress
     */
    function verifySignerAddress(bytes32 messageHash, bytes calldata signature)
        private
        view
        returns (bool)
    {
        return
            presaleSignerAddress ==
            messageHash.toEthSignedMessageHash().recover(signature);
    }

    /**
     * @notice Allow for allowlist minting of tokens
     */
    function presaleMint(
        bytes32 messageHash,
        bytes calldata signature,
        uint256 numTokens,
        uint256 maximumAllowedMints
    ) external payable nonReentrant originalUser {
        require(isPresaleActive, "PRESALE_IS_NOT_ACTIVE");

        require(
            numTokens <= presaleMintsAllowedPerTransaction,
            "MAX_MINTS_PER_TX_EXCEEDED"
        );
        require(
            _numberMinted(msg.sender) + numTokens <=
                presaleMintsAllowedPerAddress,
            "MAX_MINTS_PER_ADDRESS_EXCEEDED"
        );
        require(
            _numberMinted(msg.sender) + numTokens <= maximumAllowedMints,
            "MAX_MINTS_EXCEEDED"
        );
        require(
            totalSupply() + numTokens <= PRESALE_MAX_SUPPLY,
            "MAX_SUPPLY_EXCEEDED"
        );
        uint256 heymintFee = numTokens * heymintFeePerToken;
        require(
            msg.value == presalePrice * numTokens + heymintFee,
            "PAYMENT_INCORRECT"
        );
        require(
            keccak256(abi.encode(msg.sender, maximumAllowedMints)) ==
                messageHash,
            "MESSAGE_INVALID"
        );
        require(
            verifySignerAddress(messageHash, signature),
            "SIGNATURE_VALIDATION_FAILED"
        );

        (bool success, ) = heymintPayoutAddress.call{value: heymintFee}("");
        require(success, "Transfer failed.");
        _safeMint(msg.sender, numTokens);

        if (totalSupply() >= PRESALE_MAX_SUPPLY) {
            isPresaleActive = false;
        }
    }

    /**
     * @notice Freeze all payout addresses and percentages so they can never be changed again
     */
    function freezePayoutAddresses() external onlyOwner {
        require(!payoutAddressesFrozen, "PAYOUT_ADDRESSES_ALREADY_FROZEN");
        payoutAddressesFrozen = true;
    }

    /**
     * @notice Update payout addresses and basis points for each addresses' respective share of contract funds
     */
    function updatePayoutAddressesAndBasisPoints(
        address[] calldata _payoutAddresses,
        uint256[] calldata _payoutBasisPoints
    ) external onlyOwner {
        require(!payoutAddressesFrozen, "PAYOUT_ADDRESSES_FROZEN");
        require(
            _payoutAddresses.length == _payoutBasisPoints.length,
            "ARRAY_LENGTHS_MUST_MATCH"
        );
        uint256 totalBasisPoints = 0;
        for (uint256 i = 0; i < _payoutBasisPoints.length; i++) {
            totalBasisPoints += _payoutBasisPoints[i];
        }
        require(totalBasisPoints == 10000, "TOTAL_BASIS_POINTS_MUST_BE_10000");
        payoutAddresses = _payoutAddresses;
        payoutBasisPoints = _payoutBasisPoints;
    }

    /**
     * @notice Withdraws all funds held within contract
     */
    function withdraw() external nonReentrant onlyOwner {
        require(address(this).balance > 0, "CONTRACT_HAS_NO_BALANCE");
        uint256 balance = address(this).balance;
        for (uint256 i = 0; i < payoutAddresses.length; i++) {
            uint256 amount = (balance * payoutBasisPoints[i]) / 10000;
            (bool success, ) = payoutAddresses[i].call{value: amount}("");
            require(success, "Transfer failed.");
        }
    }

    /**
     * @notice Turn staking on or off
     */
    function setStakingState(bool _stakingState) external onlyOwner {
        require(
            isStakingActive != _stakingState,
            "NEW_STATE_IDENTICAL_TO_OLD_STATE"
        );
        isStakingActive = _stakingState;
    }

    /**
     * @notice Stake an arbitrary number of tokens
     */
    function stakeTokens(uint256[] calldata tokenIds) external {
        require(isStakingActive, "STAKING_IS_NOT_ACTIVE");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(ownerOf(tokenId) == msg.sender, "TOKEN_NOT_OWNED");
            if (currentTimeStaked[tokenId] == 0) {
                currentTimeStaked[tokenId] = block.timestamp;
                emit Stake(tokenId);
            }
        }
    }

    /**
     * @notice Unstake an arbitrary number of tokens
     */
    function unstakeTokens(uint256[] calldata tokenIds) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(ownerOf(tokenId) == msg.sender, "TOKEN_NOT_OWNED");
            if (currentTimeStaked[tokenId] != 0) {
                totalTimeStaked[tokenId] +=
                    block.timestamp -
                    currentTimeStaked[tokenId];
                currentTimeStaked[tokenId] = 0;
                emit Unstake(tokenId);
            }
        }
    }

    /**
     * @notice Allows for transfers (not sales) while staking
     */
    function stakingTransfer(
        address from,
        address to,
        uint256 tokenId
    ) external {
        require(ownerOf(tokenId) == msg.sender, "TOKEN_NOT_OWNED");
        stakingTransferActive = true;
        safeTransferFrom(from, to, tokenId);
        stakingTransferActive = false;
    }

    /**
     * @notice Allow contract owner to forcibly unstake a token if needed
     */
    function adminUnstake(uint256 tokenId) external onlyOwner {
        require(currentTimeStaked[tokenId] != 0, "TOKEN_NOT_STAKED");
        totalTimeStaked[tokenId] +=
            block.timestamp -
            currentTimeStaked[tokenId];
        currentTimeStaked[tokenId] = 0;
        emit Unstake(tokenId);
    }

    /**
     * @notice Return the total amount of time a token has been staked
     */
    function totalTokenStakeTime(uint256 tokenId)
        external
        view
        returns (uint256)
    {
        uint256 currentStakeStartTime = currentTimeStaked[tokenId];
        if (currentStakeStartTime != 0) {
            return
                (block.timestamp - currentStakeStartTime) +
                totalTimeStaked[tokenId];
        }
        return totalTimeStaked[tokenId];
    }

    /**
     * @notice Return the amount of time a token has been currently staked
     */
    function currentTokenStakeTime(uint256 tokenId)
        external
        view
        returns (uint256)
    {
        uint256 currentStakeStartTime = currentTimeStaked[tokenId];
        if (currentStakeStartTime != 0) {
            return block.timestamp - currentStakeStartTime;
        }
        return 0;
    }

    // Credit Meta Angels & Gabriel Cebrian

    modifier LoansNotPaused() {
        require(loaningActive, "LOANS_PAUSED");
        _;
    }

    /**
     * @notice To be updated by contract owner to allow for loan functionality to turned on and off
     * @param _loaningActive The new state of the loaning functionality
     */
    function setLoaningActive(bool _loaningActive) external onlyOwner {
        require(
            loaningActive != _loaningActive,
            "NEW_STATE_IDENTICAL_TO_OLD_STATE"
        );
        loaningActive = _loaningActive;
    }

    /**
     * @notice Allow owner to loan their tokens to other addresses
     */
    function loan(uint256 tokenId, address receiver)
        external
        LoansNotPaused
        nonReentrant
    {
        require(
            tokenOwnersOnLoan[tokenId] == address(0),
            "CANNOT_LOAN_LOANED_TOKEN"
        );
        require(ownerOf(tokenId) == msg.sender, "NOT_OWNER_OF_TOKEN");
        require(receiver != address(0), "CANNOT_TRANSFER_TO_ZERO_ADDRESS");
        require(receiver != msg.sender, "CANNOT_LOAN_TO_SELF");
        // Add it to the mapping of originally loaned tokens
        tokenOwnersOnLoan[tokenId] = msg.sender;
        // Add to the owner's loan balance
        totalLoanedPerAddress[msg.sender] += 1;
        currentLoanIndex += 1;
        // Transfer the token
        safeTransferFrom(msg.sender, receiver, tokenId);
        emit Loan(msg.sender, receiver, tokenId);
    }

    /**
     * @notice Allow owner to retrieve a loaned token
     */
    function retrieveLoan(uint256 tokenId) external nonReentrant {
        address borrowerAddress = ownerOf(tokenId);
        require(
            borrowerAddress != msg.sender,
            "BORROWER_CANNOT_RETRIEVE_TOKEN"
        );
        require(
            tokenOwnersOnLoan[tokenId] == msg.sender,
            "TOKEN_NOT_LOANED_BY_CALLER"
        );
        // Remove it from the array of loaned out tokens
        delete tokenOwnersOnLoan[tokenId];
        // Subtract from the owner's loan balance
        totalLoanedPerAddress[msg.sender] -= 1;
        currentLoanIndex -= 1;
        // Transfer the token back
        _directApproveMsgSenderFor(tokenId);
        safeTransferFrom(borrowerAddress, msg.sender, tokenId);
        emit LoanRetrieved(borrowerAddress, msg.sender, tokenId);
    }

    /**
     * @notice Allow contract owner to retrieve a loan to prevent malicious floor listings
     */
    function adminRetrieveLoan(uint256 tokenId) external onlyOwner {
        address borrowerAddress = ownerOf(tokenId);
        address loanerAddress = tokenOwnersOnLoan[tokenId];
        require(loanerAddress != address(0), "TOKEN_NOT_LOANED");
        // Remove it from the array of loaned out tokens
        delete tokenOwnersOnLoan[tokenId];
        // Subtract from the owner's loan balance
        totalLoanedPerAddress[loanerAddress] -= 1;
        currentLoanIndex -= 1;
        // Transfer the token back
        _directApproveMsgSenderFor(tokenId);
        safeTransferFrom(borrowerAddress, loanerAddress, tokenId);
        emit LoanRetrieved(borrowerAddress, loanerAddress, tokenId);
    }

    /**
     * Returns the total number of loaned tokens
     */
    function totalLoaned() public view returns (uint256) {
        return currentLoanIndex;
    }

    /**
     * Returns the loaned balance of an address
     */
    function loanedBalanceOf(address _owner) public view returns (uint256) {
        require(_owner != address(0), "CANNOT_QUERY_ZERO_ADDRESS");
        return totalLoanedPerAddress[_owner];
    }

    /**
     * Returns all the token ids owned by a given address
     */
    function loanedTokensByAddress(address _owner)
        external
        view
        returns (uint256[] memory)
    {
        require(_owner != address(0), "CANNOT_QUERY_ZERO_ADDRESS");
        uint256 totalTokensLoaned = loanedBalanceOf(_owner);
        uint256 mintedSoFar = totalSupply();
        uint256 tokenIdsIdx = 0;
        uint256[] memory allTokenIds = new uint256[](totalTokensLoaned);
        for (
            uint256 i = 0;
            i < mintedSoFar && tokenIdsIdx != totalTokensLoaned;
            i++
        ) {
            if (tokenOwnersOnLoan[i] == _owner) {
                allTokenIds[tokenIdsIdx] = i;
                tokenIdsIdx++;
            }
        }
        return allTokenIds;
    }

    /**
     * @notice Change the admin address used to transfer tokens if needed.
     */
    function setSoulboundAdminAddress(address _adminAddress)
        external
        onlyOwner
    {
        require(
            !soulbindAdminAddressPermanentlyDisabled,
            "CHANGING_ADMIN_ADDRESS_DISABLED"
        );
        soulboundAdminAddress = _adminAddress;
    }

    /**
     * @notice Disallow admin transfers of soulbound tokens permanently.
     */
    function disableSoulbindAdminTransfersPermanently() external onlyOwner {
        soulboundAdminAddress = address(0);
        soulbindAdminAddressPermanentlyDisabled = true;
    }

    /**
     * @notice Turn transferability on or off
     */
    function setTransferState(bool _transferState) external onlyOwner {
        transfersEnabled = _transferState;
    }

    /**
     * @notice Allows an admin address to initiate token transfers if user wallets get hacked or lost
     * This function can only be used on soulbound tokens to prevent arbitrary transfers of normal tokens
     */
    function adminTransfer(
        address from,
        address to,
        uint256 tokenId
    ) external {
        require(
            msg.sender == soulboundAdminAddress,
            "CAN_ONLY_BE_CALLED_BY_ADMIN"
        );
        soulboundAdminTransferInProgress = true;
        _directApproveMsgSenderFor(tokenId);
        safeTransferFrom(from, to, tokenId);
        soulboundAdminTransferInProgress = false;
    }

    /**
     * @notice To be updated by contract owner to allow burning to claim a token
     */
    function setBurnClaimState(bool _burnClaimActive) external onlyOwner {
        require(
            burnClaimActive != _burnClaimActive,
            "NEW_STATE_IDENTICAL_TO_OLD_STATE"
        );
        burnClaimActive = _burnClaimActive;
    }

    /**
     * @notice Update the number of free mints claimable per token burned
     */
    function updateMintsPerBurn(uint256 _mintsPerBurn) external onlyOwner {
        mintsPerBurn = _mintsPerBurn;
    }

    function burnERC721ToMint(uint256[] calldata _tokenIds)
        external
        nonReentrant
        originalUser
    {
        require(burnClaimActive, "BURN_CLAIM_IS_NOT_ACTIVE");
        uint256 numberOfTokens = _tokenIds.length;
        require(numberOfTokens > 0, "NO_TOKEN_IDS_PROVIDED");
        require(
            totalSupply() + (numberOfTokens * mintsPerBurn) <= MAX_SUPPLY,
            "MAX_SUPPLY_EXCEEDED"
        );
        ERC721A ExternalERC721BurnContract = ERC721A(burnToMintContractAddress);
        for (uint256 i = 0; i < numberOfTokens; i++) {
            require(
                ExternalERC721BurnContract.ownerOf(_tokenIds[i]) == msg.sender,
                "DOES_NOT_OWN_TOKEN_ID"
            );
            ExternalERC721BurnContract.transferFrom(
                msg.sender,
                burnAddress,
                _tokenIds[i]
            );
        }
        _safeMint(msg.sender, numberOfTokens * mintsPerBurn);
    }

    /**
     * @notice To be updated by contract owner to allow free claiming tokens
     */
    function setFreeClaimState(bool _freeClaimActive) external onlyOwner {
        require(
            freeClaimActive != _freeClaimActive,
            "NEW_STATE_IDENTICAL_TO_OLD_STATE"
        );
        freeClaimActive = _freeClaimActive;
    }

    /**
     * @notice Update the number of free mints claimable per token redeemed from the external ERC721 contract
     */
    function updateMintsPerClaim(uint256 _mintsPerClaim) external onlyOwner {
        mintsPerClaim = _mintsPerClaim;
    }

    /**
     * @notice Free claim token when msg.sender owns the token in the external contract
     */
    function freeClaim(uint256[] calldata _tokenIDs)
        external
        nonReentrant
        originalUser
    {
        require(freeClaimActive, "FREE_CLAIM_IS_NOT_ACTIVE");
        require(
            totalSupply() + (_tokenIDs.length * mintsPerClaim) <= MAX_SUPPLY,
            "MAX_SUPPLY_EXCEEDED"
        );
        ERC721A ExternalERC721FreeClaimContract = ERC721A(
            freeClaimContractAddress
        );
        for (uint256 i = 0; i < _tokenIDs.length; i++) {
            require(
                ExternalERC721FreeClaimContract.ownerOf(_tokenIDs[i]) ==
                    msg.sender,
                "DOES_NOT_OWN_TOKEN_ID"
            );
            require(!freeClaimUsed[_tokenIDs[i]], "TOKEN_ALREADY_CLAIMED");
            freeClaimUsed[_tokenIDs[i]] = true;
        }
        _safeMint(msg.sender, _tokenIDs.length * mintsPerClaim);
    }

    /**
     * @notice Generate a suitably random hash from block data
     */
    function _generateRandomHash(uint256 tokenId) internal {
        if (randomHashStore[tokenId] == bytes32(0)) {
            randomHashStore[tokenId] = keccak256(
                abi.encode(
                    block.timestamp,
                    block.difficulty,
                    blockhash(block.number - 1),
                    tokenId
                )
            );
        }
    }

    function setApprovalForAll(address operator, bool approved)
        public
        override(ERC721A, IERC721A)
        onlyAllowedOperatorApproval(operator)
    {
        require(transfersEnabled, "CANNOT_TRANSFER_SOULBOUND_TOKEN");
        super.setApprovalForAll(operator, approved);
    }

    function approve(address to, uint256 tokenId)
        public
        override(ERC721A, IERC721A)
        onlyAllowedOperatorApproval(to)
    {
        require(transfersEnabled, "CANNOT_TRANSFER_SOULBOUND_TOKEN");
        super.approve(to, tokenId);
    }

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 tokenId,
        uint256 quantity
    ) internal override(ERC721A) whenNotPaused {
        require(
            currentTimeStaked[tokenId] == 0 || stakingTransferActive,
            "TOKEN_IS_STAKED"
        );
        require(
            tokenOwnersOnLoan[tokenId] == address(0),
            "CANNOT_TRANSFER_LOANED_TOKEN"
        );
        if (!transfersEnabled && !soulboundAdminTransferInProgress) {
            require(from == address(0), "TOKEN_IS_SOULBOUND");
        }
        if (from == address(0)) {
            _generateRandomHash(tokenId);
        }

        super._beforeTokenTransfers(from, to, tokenId, quantity);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override(ERC721A, IERC721A) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override(ERC721A, IERC721A) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override(ERC721A, IERC721A) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function owner()
        public
        view
        virtual
        override(Ownable, UpdatableOperatorFilterer)
        returns (address)
    {
        return Ownable.owner();
    }
}

