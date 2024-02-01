// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./NftMinter.sol";
import "./EIP712Authorizer.sol";

/**
 * @title NUTS Dao NFT Minter
 */
contract NutsDAONFTMinter is NftMinter, EIP712Authorizer, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct RoundConfiguration {
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 maxMint;
        uint256 minMintPerAddress;
        uint256 maxMintPerAddress;
        uint256 ethPrice;
        uint256 usdcPrice;
        uint256 nutsPrice;
        bool isPrivate;
    }

    enum PaymentToken {
        NUTS,
        USDC,
        ETH
    }

    bytes32 public constant SIGN_MINT_TYPEHASH =
        keccak256("Mint(uint256 quantity,uint256 value,uint8 paymentToken,uint256 round,address account)");

    address public immutable creator;

    IERC20 public immutable nuts;
    IERC20 public immutable usdc;
    uint256 private _maxRoundId;

    mapping(uint256 => RoundConfiguration) private _rounds;
    mapping(address => mapping(uint256 => uint256)) private _userMints;
    mapping(uint256 => uint256) private _roundsMints;

    event Withdraw(uint256 amount);
    event WithdrawToken(address token, uint256 amount);

    modifier whenClaimable() {
        require(currentStatus == STATUS_READY, "Not claimable");
        _;
    }

    modifier whenValidQuantity(uint256 quantity_) {
        require(availableSupply > 0, "No more supply");
        require(availableSupply >= quantity_, "Not enough supply");
        require(quantity_ > 0, "Qty <= 0");
        _;
    }

    modifier whenRoundOpened(uint256 round_) {
        require(_rounds[round_].startTimestamp > 0, "Round not configured");
        require(_rounds[round_].startTimestamp <= block.timestamp, "Round not opened");
        require(_rounds[round_].endTimestamp == 0 || _rounds[round_].endTimestamp >= block.timestamp, "Round closed");
        _;
    }

    modifier whenRoundSupplyAvailable(uint256 round_, uint256 quantity_) {
        require(availableSupplyInRound(round_) >= quantity_, "Round supply exhausted");
        _;
    }

    constructor(
        INftCollection collection_,
        address creator_,
        IERC20 nuts_,
        IERC20 usdc_
    ) NftMinter(collection_) EIP712Authorizer("NutsDAOMinter", "1.0") {
        require(creator_ != address(0), "Invalid creator address");
        require(address(nuts_) != address(0), "Invalid nuts address");
        require(address(usdc_) != address(0), "Invalid usdc address");

        creator = creator_;
        nuts = nuts_;
        usdc = usdc_;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _syncSupply();
    }

    function _hashMintPayload(
        uint256 quantity_,
        uint256 value_,
        PaymentToken paymentToken_,
        uint256 round_,
        address account_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(SIGN_MINT_TYPEHASH, quantity_, value_, paymentToken_, round_, account_));
    }

    /**
     * @dev returns the total number of tokens minted in a round
     */
    function totalMintedTokensInRound(uint256 round_) external view returns (uint256) {
        return _roundsMints[round_];
    }

    /**
     * @dev returns the remaining supply available for a round
     * assumes a round starts after the previous is closed
     */
    function availableSupplyInRound(uint256 round_) public view returns (uint256) {
        uint256 available = 0;
        uint256 minted = 0;

        for (uint256 i = 0; i <= round_; i++) {
            available += _rounds[i].maxMint;
            minted += _roundsMints[i];
        }

        return available > minted ? available - minted : 0;
    }

    /**
     * @dev returns the total number of tokens minted by `account`
     */
    function mintedTokensCount(address account) external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i <= _maxRoundId; i++) {
            total += _userMints[account][i];
        }
        return total;
    }

    /**
     * @dev returns the number of tokens minted by `account` for a specific round
     */
    function mintedTokensInRound(address account, uint256 round) external view returns (uint256) {
        return _userMints[account][round];
    }

    /**
     * @dev returns the configuration for a round
     */
    function getRound(uint256 round_) external view returns (RoundConfiguration memory) {
        return _rounds[round_];
    }

    /**
     * @dev configure the round
     */
    function configureRound(uint256 round_, RoundConfiguration calldata configuration_) external onlyOwnerOrOperator {
        require(
            configuration_.endTimestamp == 0 || configuration_.startTimestamp < configuration_.endTimestamp,
            "Invalid timestamps"
        );
        require(configuration_.maxMint > 0, "Invalid max mint");
        require(configuration_.minMintPerAddress > 0, "Invalid min mint per address");
        require(configuration_.maxMintPerAddress > 0, "Invalid max mint per address");
        require(configuration_.maxMintPerAddress >= configuration_.minMintPerAddress, "Invalid mint per address");
        _rounds[round_] = configuration_;
        if (_maxRoundId < round_) {
            _maxRoundId = round_;
        }
    }

    /**
     * @dev returns the price in token or ETH for a round
     */
    function getPrice(uint256 round_, PaymentToken paymentToken_) public view returns (uint256) {
        if (paymentToken_ == PaymentToken.NUTS)
            return _rounds[round_].nutsPrice;
        else if (paymentToken_ == PaymentToken.USDC)
            return _rounds[round_].usdcPrice;
        else if (paymentToken_ == PaymentToken.ETH)
            return _rounds[round_].ethPrice;
        return 0;
    }

    /**
     * @dev mint a `quantity_` NFT (quantity max for a wallet is limited per round)
     * round_: Round Id
     * paymentToken_: token used to pay the transaction
     * signature_: backend signature for the transaction
     */
    function mint(
        uint256 quantity_,
        uint256 round_,
        PaymentToken paymentToken_,
        bytes memory signature_
    )
        external
        payable
        nonReentrant
        whenValidQuantity(quantity_)
        whenRoundSupplyAvailable(round_, quantity_)
        whenClaimable
        whenRoundOpened(round_)
    {
        address to = _msgSender();
        RoundConfiguration memory round = _rounds[round_];
        require(_userMints[to][round_] + quantity_ >= round.minMintPerAddress, "Below quantity allowed");
        require(_userMints[to][round_] + quantity_ <= round.maxMintPerAddress, "Above quantity allowed");
        require(paymentToken_ <= PaymentToken.ETH, "Invalid payment token");

        uint256 value = getPrice(round_, paymentToken_) * quantity_;
        if (round.isPrivate) {
            require(
                isAuthorized(_hashMintPayload(quantity_, value, paymentToken_, round_, to), signature_),
                "Not signed by authorizer"
            );
        }

        _userMints[to][round_] += quantity_;
        _roundsMints[round_] += quantity_;

        if (paymentToken_ == PaymentToken.NUTS) {
            nuts.safeTransferFrom(to, address(this), value);
        } else if (paymentToken_ == PaymentToken.USDC) {
            usdc.safeTransferFrom(to, address(this), value);
        } else {
            // PaymentToken.ETH
            require(msg.value >= value, "Payment failed");
        }

        _mint(quantity_, to);
    }

    /**
     * @dev mint the remaining NFTs when the sale is closed
     */
    function mintRemaining(address destination_, uint256 quantity_)
        external
        onlyOwnerOrOperator
        whenValidQuantity(quantity_)
    {
        require(currentStatus == STATUS_CLOSED, "Status not closed");
        _mint(quantity_, destination_);
    }

    function _withdraw(uint256 amount) private {
        require(amount <= address(this).balance, "amount > balance");
        require(amount > 0, "Empty amount");

        payable(creator).transfer(amount);
        emit Withdraw(amount);
    }

    /**
     * @dev withdraw selected amount
     */
    function withdraw(uint256 amount) external onlyOwnerOrOperator {
        _withdraw(amount);
    }

    /**
     * @dev withdraw full balance
     */
    function withdrawAll() external onlyOwnerOrOperator {
        _withdraw(address(this).balance);
    }

    /**
     * @dev withdraw amount of Tokens and send it to CREATOR
     */
    function withdrawToken(address token, uint256 amount) external onlyOwnerOrOperator {
        IERC20(token).safeTransfer(creator, amount);
        emit WithdrawToken(token, amount);
    }

    /**
     * @dev withdraw all Tokens and send it to CREATOR
     */
    function withdrawAllTokens() external onlyOwnerOrOperator {
        uint256 balance = nuts.balanceOf(address(this));
        if (balance > 0) {
            nuts.safeTransfer(creator, balance);
            emit WithdrawToken(address(nuts), balance);
        }

        balance = usdc.balanceOf(address(this));
        if (balance > 0) {
            usdc.safeTransfer(creator, balance);
            emit WithdrawToken(address(usdc), balance);
        }
    }
}

