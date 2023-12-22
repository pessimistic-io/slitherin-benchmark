pragma solidity ^0.8.0;
import "./IWETH.sol";
import "./BoringERC20.sol";
import "./Ownable.sol";
import "./VibeERC721.sol";
import "./IDistributor.sol";
import "./SimpleFactory.sol";

// ⢠⣶⣿⣿⣶⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⣿⣿⠁⠀⠙⢿⣦⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠸⣿⣆⠀⠀⠈⢻⣷⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣾⡿⠿⠛⠻⠿⣿⣦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣤⣤⣤⣀⡀⠀
// ⠀⢻⣿⡆⠀⠀⠀⢻⣷⡀⠀⠀⠀⠀⠀⠀⢀⣴⣾⠿⠿⠿⣿⣿⠀⠀⠀⠀⠀⠈⢻⣷⡀⠀⠀⠀⠀⠀⢀⣠⣶⣿⠿⠛⠋⠉⠉⠻⣿⣦
// ⠀⠀⠻⣿⡄⠀⠀⠀⢿⣧⣠⣶⣾⠿⠿⠿⣿⡏⠀⠀⠀⠀⢹⣿⡀⠀⠀⠀⢸⣿⠈⢿⣷⠀⠀⠀⢀⣴⣿⠟⠉⠀⠀⠀⠀⠀⠀⠀⢸⣿
// ⠀⠀⠀⠹⣿⡄⠀⠀⠈⢿⣿⡏⠀⠀⠀⠀⢻⣷⠀⠀⠀⠀⠸⣿⡇⠀⠀⠀⠈⣿⠀⠘⢿⣧⣠⣶⡿⠋⠁⠀⠀⠀⠀⠀⠀⣀⣠⣤⣾⠟
// ⠀⠀⠀⠀⢻⣿⡄⠀⠀⠘⣿⣷⠀⠀⠀⠀⢸⣿⡀⠀⠀⠀⠀⣿⣷⠀⠀⠀⠀⣿⠀⢶⠿⠟⠛⠉⠀⠀⠀⠀⠀⢀⣤⣶⠿⠛⠋⠉⠁⠀
// ⠀⠀⠀⠀⠀⢿⣷⠀⠀⠀⠘⣿⡆⠀⠀⠀⠀⣿⡇⠀⠀⠀⠀⢹⣿⠀⠀⠀⠀⣿⡆⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⡿⠋⠁⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠘⣿⡇⠀⠀⠀⢸⣷⠀⠀⠀⠀⢿⣷⠀⠀⠀⠀⠈⣿⡇⠀⠀⠀⣿⡇⠀⠀⠀⠀⠀⠀⠀⣴⣿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⢻⣿⠀⠀⠀⠀⢿⣇⠀⠀⠀⠸⣿⡄⠀⠀⠀⠀⣿⣷⠀⠀⠀⣿⡇⠀⠀⠀⠀⠀⠀⣼⡿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠘⣿⡇⠀⠀⠀⠸⣿⡀⠀⠀⠀⢿⣇⠀⠀⠀⠀⢸⣿⡀⠀⢠⣿⠇⠀⠀⠀⠀⠀⣼⡿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⢹⣿⠀⠀⠀⠀⢻⣧⠀⠀⠀⠸⣿⡄⠀⠀⠀⢘⣿⡿⠿⠟⠋⠀⠀⠀⠀⠀⣼⣿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠈⣿⣇⠀⠀⠀⠈⣿⣄⠀⢀⣠⣿⣿⣶⣶⣶⡾⠋⠀⠀⠀⠀⠀⠀⠀⠀⣰⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⢹⣿⡀⠀⠀⠀⠈⠻⠿⠟⠛⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⢻⣷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢿⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢻⣧⡀⠀⠀⠀⣀⠀⠀⠀⣴⣤⣄⣀⣀⣀⣠⣤⣾⣿⡿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠹⣿⣶⣶⣿⡿⠃⠀⠀⠉⠛⠻⠿⠿⠿⠿⢿⣿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣿⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢿⣇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀

abstract contract MintSaleBase is Ownable {
    using BoringERC20 for IERC20;
    event SaleExtended(uint32 newEndTime);
    event SaleEnded();
    event SaleEndedEarly();
    event TokensClaimed(uint256 total, uint256 fee, address proceedRecipient);

    uint256 public constant BPS = 100_000;

    IWETH public immutable WETH;
    address private immutable masterNFT;
    SimpleFactory public immutable vibeFactory;

    VibeERC721 public nft;
    uint32 public beginTime;
    uint32 public endTime;

    IERC20 public paymentToken;
    
    constructor(address masterNFT_, SimpleFactory vibeFactory_, IWETH WETH_) {
        masterNFT = masterNFT_;
        vibeFactory = vibeFactory_;
        WETH = WETH_;
    }

    struct VibeFees {
        address vibeTreasury;
        uint96 feeTake;
    }

    VibeFees public fees;


    modifier onlyMasterContractOwner {
        address master = vibeFactory.masterContractOf(address(this));
        if (master != address(0)) {
            require(Ownable(master).owner() == msg.sender);
        }
        _;
    }

    /// @notice Sets the VibeFees for the contract.
    /// @param vibeTreasury_ The address of the Vibe treasury.
    /// @param feeTake_ The fee percentage in basis points.
    function setVibeFees(address vibeTreasury_, uint96 feeTake_) external onlyMasterContractOwner {
        fees = VibeFees(vibeTreasury_, feeTake_);
    }


    function getPayment(IERC20 paymentToken, uint256 amount) internal {
        if (address(paymentToken) == address(WETH)) {
            WETH.deposit{value: amount}();
        } else {
            paymentToken.safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function claimEarnings(address proceedRecipient) public onlyOwner {
        uint256 total = paymentToken.balanceOf(address(this));
        uint256 fee = total * uint256(fees.feeTake) / BPS;
        paymentToken.safeTransfer(proceedRecipient, total - fee);
        paymentToken.safeTransfer(fees.vibeTreasury, fee);

        if (proceedRecipient.code.length > 0) {
            (bool success, bytes memory result) = proceedRecipient.call(abi.encodeWithSignature("supportsInterface(bytes4)", type(IDistributor).interfaceId));
            if (success) {
                (bool distribute) = abi.decode(result, (bool));
                if (distribute) {
                    IDistributor(proceedRecipient).distribute(paymentToken, total - fee);
                }
            }
        }

        emit TokensClaimed(total, fee, proceedRecipient);
    }

    /// @notice Removes tokens and reclaims ownership of the NFT contract after the sale has ended.
    /// @dev The sale must have ended before calling this function.
    /// @param proceedRecipient The address that will receive the proceeds from the sale.
    function removeTokensAndReclaimOwnership(address proceedRecipient) external onlyOwner {
        if(block.timestamp < endTime){
            endTime = uint32(block.timestamp);
            emit SaleEndedEarly();
        } else {
            emit SaleEnded();
        }
        claimEarnings(proceedRecipient);
        nft.renounceMinter();
    }

    /// @notice Extends the sale end time to a new timestamp.
    /// @dev The new end time must be in the future.
    /// @param newEndTime The new end time for the sale.
    function extendEndTime(uint32 newEndTime) external onlyOwner {
        require(newEndTime > block.timestamp);
        endTime = newEndTime;

        emit SaleExtended(endTime);
    }
}
