// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.13;

import "./ERC721Enumerable.sol";
import "./ERC2981.sol";
import "./Ownable.sol";
import "./Address.sol";
import "./EnumerableSet.sol";

import "./IEtherealSpheres.sol";

contract EtherealSpheres is IEtherealSpheres, ERC721Enumerable, ERC2981, Ownable {
    using Address for address payable;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant MAXIMUM_NUMBER_OF_TOKENS_TO_RESERVE = 150;
    uint256 public constant MAXIMUM_NUMBER_OF_TOKENS_TO_MINT_PER_ACCOUNT_DURING_WHITELIST_PERIOD = 10;
    uint256 public constant MAXIMUM_NUMBER_OF_TOKENS_TO_MINT_PER_ACCOUNT_DURING_PUBLIC_PERIOD = 15;
    uint96 public constant ROYALTY_PERCENTAGE = 300;

    uint256 public immutable maximumSupply;
    uint256 public price;
    uint256 public availableNumberOfTokensToMint;
    uint256 public numberOfReservedTokens;
    uint256 private _nextTokenId = 1;
    address payable public treasury;
    IOriginalMintersPool public originalMintersPool;
    string public baseURI;
    Period public period;

    EnumerableSet.AddressSet private _privatePeriodAccounts;
    EnumerableSet.AddressSet private _whitelistPeriodAccounts;
    EnumerableSet.AddressSet private _originalMinters;

    mapping(address => uint256) public numberOfMintedTokensDuringWhitelistPeriodByAccount;
    mapping(address => uint256) public numberOfMintedTokensDuringPublicPeriodByAccount;

    /// @param maximumSupply_ Maximum supply.
    /// @param price_ Minting price per token.
    /// @param treasury_ Treasury address.
    /// @param royaltyDistributor_ RoyaltyDistributor contract address.
    /// @param baseURI_ Base URI.
    constructor(
        uint256 maximumSupply_,
        uint256 price_,
        address payable treasury_,
        address royaltyDistributor_,
        string memory baseURI_
    )
        ERC721("Ethereal Spheres", "hraNFT")
    {
        maximumSupply = maximumSupply_;
        price = price_;
        treasury = treasury_;
        baseURI = baseURI_;
        _setDefaultRoyalty(royaltyDistributor_, ROYALTY_PERCENTAGE);
    }

    /// @inheritdoc IEtherealSpheres
    function addAccountsToWhitelist(address[] calldata accounts_, Period period_) external onlyOwner {
        if (period_ == Period.PRIVATE) {
            for (uint256 i = 0; i < accounts_.length; ) {
                _privatePeriodAccounts.add(accounts_[i]);
                unchecked {
                    i++;
                }
            }
        } else if (period_ == Period.WHITELIST) {
            for (uint256 i = 0; i < accounts_.length; ) {
                _whitelistPeriodAccounts.add(accounts_[i]);
                unchecked {
                    i++;
                }
            }
        } else {
            revert InvalidPeriod();
        }
    }

    /// @inheritdoc IEtherealSpheres
    function removeAccountsFromWhitelist(address[] calldata accounts_, Period period_) external onlyOwner {
        if (period_ == Period.PRIVATE) {
            for (uint256 i = 0; i < accounts_.length; ) {
                _privatePeriodAccounts.remove(accounts_[i]);
                unchecked {
                    i++;
                }
            }
        } else if (period_ == Period.WHITELIST) {
            for (uint256 i = 0; i < accounts_.length; ) {
                _whitelistPeriodAccounts.remove(accounts_[i]);
                unchecked {
                    i++;
                }
            }
        } else {
            revert InvalidPeriod();
        }
    }

    /// @inheritdoc IEtherealSpheres
    function updateOriginalMintersPool(IOriginalMintersPool originalMintersPool_) external onlyOwner {
        emit OriginalMintersPoolUpdated(originalMintersPool, originalMintersPool_);
        originalMintersPool = originalMintersPool_;
    }

    /// @inheritdoc IEtherealSpheres
    function updatePeriod(Period period_) external onlyOwner {
        emit PeriodUpdated(period, period_);
        period = period_;
    }

    /// @inheritdoc IEtherealSpheres
    function updatePrice(uint256 price_) external onlyOwner {
        emit TokenPriceUpdated(price, price_);
        price = price_;
    }

    /// @inheritdoc IEtherealSpheres
    function updateTreasury(address payable treasury_) external onlyOwner {
        emit TreasuryUpdated(treasury, treasury_);
        treasury = treasury_;
    }

    /// @inheritdoc IEtherealSpheres
    function updateBaseURI(string calldata baseURI_) external onlyOwner {
        emit BaseURIUpdated(baseURI, baseURI_);
        baseURI = baseURI_;
    }

    /// @inheritdoc IEtherealSpheres
    function increaseAvailableNumberOfTokensToMint(uint256 numberOfTokens_) external onlyOwner {
        uint256 m_availableNumberOfTokensToMint = availableNumberOfTokensToMint;
        if (
            totalSupply() + numberOfTokens_ > maximumSupply || 
            m_availableNumberOfTokensToMint + numberOfTokens_ > maximumSupply
        ) {
            revert InvalidNumberOfTokens();
        }
        unchecked {
            availableNumberOfTokensToMint += numberOfTokens_;
            emit AvailableNumberOfTokensToMintIncreased(
                m_availableNumberOfTokensToMint, 
                m_availableNumberOfTokensToMint + numberOfTokens_, 
                numberOfTokens_
            );
        }
    }

    /// @inheritdoc IEtherealSpheres
    function decreaseAvailableNumberOfTokensToMint(uint256 numberOfTokens_) external onlyOwner {
        uint256 m_availableNumberOfTokensToMint = availableNumberOfTokensToMint;
        availableNumberOfTokensToMint -= numberOfTokens_;
        unchecked {
            emit AvailableNumberOfTokensToMintDecreased(
                m_availableNumberOfTokensToMint,
                m_availableNumberOfTokensToMint - numberOfTokens_, 
                numberOfTokens_
            );
        }
    }

    /// @inheritdoc IEtherealSpheres
    function withdraw() external onlyOwner {
        treasury.sendValue(address(this).balance);
    }

    /// @inheritdoc IEtherealSpheres
    function reserve(address account_, uint256 numberOfTokens_) external onlyOwner {
        if (numberOfReservedTokens + numberOfTokens_ > MAXIMUM_NUMBER_OF_TOKENS_TO_RESERVE) {
            revert ForbiddenToMintMore();
        }
        uint256 m_nextTokenId = _nextTokenId;
        for (uint256 i = 0; i < numberOfTokens_; ) {
            _safeMint(account_, m_nextTokenId);
            unchecked {
                m_nextTokenId++;
                i++;
            }
        }
        _nextTokenId = m_nextTokenId;
        availableNumberOfTokensToMint -= numberOfTokens_;
        unchecked {
            numberOfReservedTokens += numberOfTokens_;
        }
    }

    /// @inheritdoc IEtherealSpheres
    function privatePeriodMint(uint256 numberOfTokens_) external payable {
        if (numberOfTokens_ == 0) {
            revert ZeroEntry();
        }
        if (msg.value != price * numberOfTokens_) {
            revert InvalidMsgValue();
        }
        if (period != Period.PRIVATE) {
            revert InvalidPeriod();
        }
        if (!_privatePeriodAccounts.contains(msg.sender)) {
            revert ForbiddenToMint();
        }
        if (!_originalMinters.contains(msg.sender)) {
            _originalMinters.add(msg.sender);
        }
        uint256 m_nextTokenId = _nextTokenId;
        for (uint256 i = 0; i < numberOfTokens_; ) {
            _safeMint(msg.sender, m_nextTokenId);
            unchecked {
                m_nextTokenId++;
                i++;
            }
        }
        _nextTokenId = m_nextTokenId;
        originalMintersPool.updateStakeFor(msg.sender, numberOfTokens_);
        availableNumberOfTokensToMint -= numberOfTokens_;
    }

    /// @inheritdoc IEtherealSpheres
    function whitelistPeriodMint(uint256 numberOfTokens_) external payable {
        if (numberOfTokens_ == 0) {
            revert ZeroEntry();
        }
        if (msg.value != price * numberOfTokens_) {
            revert InvalidMsgValue();
        }
        if (period != Period.WHITELIST) {
            revert InvalidPeriod();
        }
        if (!_whitelistPeriodAccounts.contains(msg.sender)) {
            revert ForbiddenToMint();
        }
        if (
            numberOfMintedTokensDuringWhitelistPeriodByAccount[msg.sender] 
            + numberOfTokens_ 
            > MAXIMUM_NUMBER_OF_TOKENS_TO_MINT_PER_ACCOUNT_DURING_WHITELIST_PERIOD
        ) {
            revert ForbiddenToMintMore();
        }
        if (!_originalMinters.contains(msg.sender)) {
            _originalMinters.add(msg.sender);
        }
        uint256 m_nextTokenId = _nextTokenId;
        for (uint256 i = 0; i < numberOfTokens_; ) {
            _safeMint(msg.sender, m_nextTokenId);
            unchecked {
                m_nextTokenId++;
                i++;
            }
        }
        _nextTokenId = m_nextTokenId;
        originalMintersPool.updateStakeFor(msg.sender, numberOfTokens_);
        availableNumberOfTokensToMint -= numberOfTokens_;
        unchecked {
            numberOfMintedTokensDuringWhitelistPeriodByAccount[msg.sender] += numberOfTokens_;
        }
    }

    /// @inheritdoc IEtherealSpheres
    function publicPeriodMint(uint256 numberOfTokens_) external payable {
        if (numberOfTokens_ == 0) {
            revert ZeroEntry();
        }
        if (msg.value != price * numberOfTokens_) {
            revert InvalidMsgValue();
        }
        if (period != Period.PUBLIC) {
            revert InvalidPeriod();
        }
        if (
            numberOfMintedTokensDuringPublicPeriodByAccount[msg.sender] 
            + numberOfTokens_
            > MAXIMUM_NUMBER_OF_TOKENS_TO_MINT_PER_ACCOUNT_DURING_PUBLIC_PERIOD
        ) {
            revert ForbiddenToMintMore();
        }
        if (!_originalMinters.contains(msg.sender)) {
            _originalMinters.add(msg.sender);
        }
        uint256 m_nextTokenId = _nextTokenId;
        for (uint256 i = 0; i < numberOfTokens_; ) {
            _safeMint(msg.sender, m_nextTokenId);
            unchecked {
                m_nextTokenId++;
                i++;
            }
        }
        _nextTokenId = m_nextTokenId;
        originalMintersPool.updateStakeFor(msg.sender, numberOfTokens_);
        availableNumberOfTokensToMint -= numberOfTokens_;
        unchecked {
            numberOfMintedTokensDuringPublicPeriodByAccount[msg.sender] += numberOfTokens_;
        }
    }

    /// @inheritdoc IEtherealSpheres
    function isPrivatePeriodAccount(address account_) external view returns (bool) {
        return _privatePeriodAccounts.contains(account_);
    }

    /// @inheritdoc IEtherealSpheres
    function privatePeriodAccountsLength() external view returns (uint256) {
        return _privatePeriodAccounts.length();
    }

    /// @inheritdoc IEtherealSpheres
    function privatePeriodAccountAt(uint256 index_) external view returns (address) {
        return _privatePeriodAccounts.at(index_);
    }

    /// @inheritdoc IEtherealSpheres
    function isWhitelistPeriodAccount(address account_) external view returns (bool) {
        return _whitelistPeriodAccounts.contains(account_);
    }

    /// @inheritdoc IEtherealSpheres
    function whitelistPeriodAccountsLength() external view returns (uint256) {
        return _whitelistPeriodAccounts.length();
    }

    /// @inheritdoc IEtherealSpheres
    function whitelistPeriodAccountAt(uint256 index_) external view returns (address) {
        return _whitelistPeriodAccounts.at(index_);
    }

    /// @inheritdoc IEtherealSpheres
    function isOriginalMinter(address account_) external view returns (bool) {
        return _originalMinters.contains(account_);
    }

    /// @inheritdoc IEtherealSpheres
    function originalMintersLength() external view returns (uint256) {
        return _originalMinters.length();
    }

    /// @inheritdoc IEtherealSpheres
    function originalMinterAt(uint256 index_) external view returns (address) {
        return _originalMinters.at(index_);
    }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId_
    )
        public
        view
        override(ERC721Enumerable, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId_);
    }

    /// @inheritdoc ERC721
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}
