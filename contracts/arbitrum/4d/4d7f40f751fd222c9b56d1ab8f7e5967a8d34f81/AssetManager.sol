// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./AccessControl.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20Metadata.sol";
import "./IBalanceSheet.sol";
import "./IAssetManager.sol";
import "./IQualifier.sol";

//   /$$$$$$$            /$$$$$$$$
//  | $$__  $$          | $$_____/
//  | $$  \ $$  /$$$$$$ | $$     /$$$$$$  /$$$$$$   /$$$$$$
//  | $$  | $$ /$$__  $$| $$$$$ /$$__  $$|____  $$ /$$__  $$
//  | $$  | $$| $$$$$$$$| $$__/| $$  \__/ /$$$$$$$| $$  \ $$
//  | $$  | $$| $$_____/| $$   | $$      /$$__  $$| $$  | $$
//  | $$$$$$$/|  $$$$$$$| $$   | $$     |  $$$$$$$|  $$$$$$$
//  |_______/  \_______/|__/   |__/      \_______/ \____  $$
//                                                 /$$  \ $$
//                                                |  $$$$$$/
//                                                 \______/

/// @title Asset Manager is in charge of moving and holding assets such as ERC20s and ERC721s
/// @author DeFragDAO
/// @custom:experimental This is an experimental contract
contract AssetManager is
    IAssetManager,
    IERC721Receiver,
    ReentrancyGuard,
    Pausable,
    AccessControl
{
    address public immutable nftCollectionAddress;
    address public immutable erc20Address;
    address public immutable qualifierAddress;
    address public immutable balanceSheetAddress;
    address public immutable treasuryAddress;

    bytes32 public constant DEFRAG_SYSTEM_ADMIN_ROLE =
        keccak256("DEFRAG_SYSTEM_ADMIN_ROLE");
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    event DepositedCollateral(
        address indexed _from,
        address _to,
        uint256 _tokenID,
        bytes _data
    );

    event WithdrewCollateral(
        address indexed _to,
        address _from,
        uint256 _tokenID
    );

    event Borrowed(
        address indexed _user,
        uint256[] _collateralTokenIds,
        uint256 _borrowedAmount
    );

    event PaidAmount(
        address indexed _payer,
        address indexed _userWithLoan,
        uint256 _paymentAmount
    );

    event WithdrewETH(
        address indexed _operator,
        address indexed _to,
        uint256 _withdrewAmount
    );

    event WithdrewERC20(
        address indexed _operator,
        address indexed _to,
        uint256 _withdrewAmount,
        address _interactedWithTokenContract
    );

    event WithdrewERC721(
        address indexed _operator,
        address indexed _to,
        uint256 _withdrewTokenId,
        address _interactedWithTokenContract
    );

    event Liquidated(address indexed _user, address _to, uint256 _tokenId);

    event SentToTreasuryAmount(address indexed _to, uint256 _amount);

    constructor(
        address _nftCollectionAddress,
        address _erc20Address,
        address _qualifierAddress,
        address _balanceSheetAddress,
        address _treasuryAddress
    ) {
        nftCollectionAddress = _nftCollectionAddress;
        erc20Address = _erc20Address;
        qualifierAddress = _qualifierAddress;
        balanceSheetAddress = _balanceSheetAddress;
        treasuryAddress = _treasuryAddress;

        _pause();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice borrow and deposit collateral
     * @dev user must approve the ERC721 asset for transfer before
     * @param _tokenIds - token ID array
     * @param _amount - amount
     */
    function borrow(
        uint256[] memory _tokenIds,
        uint256 _amount
    ) public nonReentrant whenNotPaused {
        // check if user is on allow list
        require(
            IQualifier(qualifierAddress).isUserAllowListed(msg.sender),
            "AssetManager: User not on allow list"
        );

        // check if acceptable NFT tokenIds
        if (_tokenIds.length > 0) {
            for (uint256 i = 0; i < _tokenIds.length; i++) {
                require(
                    IQualifier(qualifierAddress).isTokenIdAllowListed(
                        _tokenIds[i]
                    ),
                    "AssetManager: Token ID not on allow list"
                );
            }
        }

        // make sure msg.sender is the owner of the token
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            try IERC721(nftCollectionAddress).ownerOf(_tokenIds[i]) {
                require(
                    IERC721(nftCollectionAddress).ownerOf(_tokenIds[i]) ==
                        msg.sender,
                    "AssetManager: not an owner of token"
                );
            } catch {
                revert("AssetManager: can't verify ownership");
            }
        }

        // check if there are enough stable coins to lend
        require(
            IERC20Metadata(erc20Address).balanceOf(address(this)) >=
                amountInUSDC(_amount),
            "AssetManager: not enough stables"
        );

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _depositNFT(_tokenIds[i]);
        }

        IERC20Metadata(erc20Address).transfer(
            msg.sender,
            amountInUSDC(_amount)
        );
        IBalanceSheet(balanceSheetAddress).setLoan(
            msg.sender,
            _tokenIds,
            _amount
        );

        emit Borrowed(msg.sender, _tokenIds, _amount);
    }

    /**
     * @notice make a payment for the loan
     * @dev user must approve the ERC20 asset for transfer before
     * @param _amount amount of USDC
     */
    function makePayment(uint256 _amount, address _userAddress) public {
        require(
            IERC20Metadata(erc20Address).balanceOf(address(msg.sender)) >=
                amountInUSDC(_amount),
            "AssetManager: not enough owned"
        );

        uint256 claimableFees = IBalanceSheet(balanceSheetAddress).setPayment(
            _userAddress,
            _amount
        );

        if (claimableFees > 0) {
            IERC20Metadata(erc20Address).transferFrom(
                msg.sender,
                address(this),
                amountInUSDC(_amount) - amountInUSDC(claimableFees)
            );

            IERC20Metadata(erc20Address).transferFrom(
                msg.sender,
                treasuryAddress,
                amountInUSDC(claimableFees)
            );

            emit SentToTreasuryAmount(treasuryAddress, claimableFees);
        } else {
            IERC20Metadata(erc20Address).transferFrom(
                msg.sender,
                address(this),
                amountInUSDC(_amount)
            );
        }

        emit PaidAmount(msg.sender, _userAddress, _amount);
    }

    /**
     * @notice withdraw collateral
     * @param _tokenIds - array of token ids
     */
    function withdrawCollateral(uint256[] memory _tokenIds) public {
        address user = msg.sender;

        IBalanceSheet(balanceSheetAddress).removeCollateral(
            msg.sender,
            _tokenIds
        );

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            IERC721(nftCollectionAddress).safeTransferFrom(
                address(this),
                user,
                _tokenIds[i]
            );
            emit WithdrewCollateral(user, address(this), _tokenIds[i]);
        }
    }

    /**
     * @notice liqudate the user - move tokens to treasury and null out the loan in balance sheet
     * @param _userAddress - address of the user
     */
    function liquidate(address _userAddress) public onlyLiquidator {
        uint256[] memory tokenIds = IBalanceSheet(balanceSheetAddress)
            .getTokenIds(_userAddress);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            IERC721(nftCollectionAddress).safeTransferFrom(
                address(this),
                treasuryAddress,
                tokenIds[i]
            );

            emit Liquidated(_userAddress, treasuryAddress, tokenIds[i]);
        }

        IBalanceSheet(balanceSheetAddress).nullifyLoan(_userAddress);
    }

    /**
     * @dev override for IERC721Receiver
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public override returns (bytes4) {
        emit DepositedCollateral(from, operator, tokenId, data);
        return this.onERC721Received.selector;
    }

    /**
     * @notice pause borrowing
     */
    function pauseLoans() public onlyAdmin {
        _pause();
    }

    /**
     * @notice unpause borrowing
     */
    function unpauseLoans() public onlyAdmin {
        _unpause();
    }

    /**
     * @notice withdraw eth
     * @param _to - address
     * @param _amount - amount
     */
    function withdrawEth(address _to, uint256 _amount) public onlyAdmin {
        (bool sent, ) = _to.call{value: _amount}("");
        require(sent, "Failed to send Ether");
        emit WithdrewETH(msg.sender, _to, _amount);
    }

    /**
     * @notice withdraw erc20
     * @param _to - address
     * @param _amount - amount
     * @param _tokenAddress - token address
     */
    function withdrawERC20(
        address _to,
        uint256 _amount,
        address _tokenAddress
    ) public onlyAdmin {
        IERC20Metadata(_tokenAddress).transfer(_to, _amount);
        emit WithdrewERC20(msg.sender, _to, _amount, _tokenAddress);
    }

    /**
     * @notice withdraw erc721
     * @param _tokenId - token ID
     * @param _tokenAddress - token address
     */
    function withdrawERC721(
        address _to,
        uint256 _tokenId,
        address _tokenAddress
    ) public onlyAdmin {
        IERC721(_tokenAddress).safeTransferFrom(address(this), _to, _tokenId);
        emit WithdrewERC721(msg.sender, _to, _tokenId, _tokenAddress);
    }

    /**
     * @notice helper to convert wei into USDC
     * @param _amount - 18 decimal amount
     * @return uint256 - USDC decimal compliant amount
     */
    function amountInUSDC(uint256 _amount) public view returns (uint256) {
        // because USDC is 6 decimals, we need to fix the decimals
        // https://docs.openzeppelin.com/contracts/4.x/erc20#a-note-on-decimals
        uint8 decimals = IERC20Metadata(erc20Address).decimals();
        return (_amount / 10 ** (18 - decimals));
    }

    /**
     * @notice transfer the NFT to Asset Manager
     * @param _tokenId - token ID array
     */
    function _depositNFT(uint256 _tokenId) internal {
        IERC721(nftCollectionAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenId
        );
    }

    modifier onlyAdmin() {
        require(
            hasRole(DEFRAG_SYSTEM_ADMIN_ROLE, msg.sender),
            "AssetManager: only DefragSystemAdmin"
        );
        _;
    }

    modifier onlyLiquidator() {
        require(
            hasRole(LIQUIDATOR_ROLE, msg.sender),
            "AssetManager: only Liquidator"
        );
        _;
    }
}

