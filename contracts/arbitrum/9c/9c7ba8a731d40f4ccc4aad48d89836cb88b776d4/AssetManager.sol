// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./AccessControl.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20Metadata.sol";
import {IBalanceSheet} from "./IBalanceSheet.sol";
import {IAssetManager} from "./IAssetManager.sol";
import {ISmolSchool} from "./ISmolSchool.sol";

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
//
//  ASSISTANT TO THE ASSET MANAGER
//
//                            `/+o/.
//                        .+sso+/:oydyo/:-:+shdys/    `-:.     `-/+o+/`
//                  `/sdh+/::/::ss:`ymdhyso//hmMNyhNNms+ososys+/-:/shms/`
//                 .+hNNy++oo+/.`.--/osyhdmNNMMMMMMMMMNdsssssoso+hhhhsoo+ymdo.
//               -smNy/+ymmmmmNNNNMNMMMMMNNNmmNMMMMMMMMMho:///:--shydNMMNdo-sNs`
//             -hNd+-sNMNdmNMMMNNNMNNNMMMddNMMNNmNMMMMMMNmy+///::/:-:/++ymNNdmMN:
//           `sNMs`+NMNNNMMMMNNNMMMMMMNmhyso///+ohMmoNMmoo+/::/-:oymNNmsosshdhmMM/
//          +NMMy`hMMMhyNMNMMNNNMds:-.`-:syddmNMMmyo`+yMMho:..-+//++omMNNNNNNNmdNMs
//        :mMMMh`yMNdodNNNMNMMMs.+sdmmmmmdhNMMMNhy/..`-syhNmdyssso+/.`:yNMMMMNMNMMMy
//       :NMNh:-+MMh+mdNNNNNMd.+NNMMMMMMMMmho:-......:--::ohNMMMMMMNmNy/.oNMNmNMNMMMs
//      :NMm+/dmmMNydyhNdhMMN.yMMNmhysso+:-``        ```.--:/+sdMMMMMNNNm:-mMNNNNMMMMy
//     :NMy/hNMMMMmNddsh/NmMy-Mms:..`.--.`                ``..-.:yNMMMMNMNs:NMMMNNNNMMy
//    :NNy/mMMMMMMmNMMshsNdMo/d-...``                       ```...-yMMMNNMd`NMMNMdmoNMM-
//   /mMm+NMNNMMNMNNNNNNNNMMmom/                              ```..`+NMMMMh`NMMMMNNdhNMh
//  +NMMmmMNyNMNMMMMMNmmmNMdNNyh+.                             ``````/NMMM::MMMMNMNNmNMN
// +MNNMMMNymMNNMMMNNNNNMh+:+dNmddhyoo+`                        ````.`sMMN`sMNNMNNMNNNNN
// dNNNMNNddMNNNNNNmymMN+---::/shdhyyy:                         `````..hMo.NMNMNMMMNmMMd
// dNNNMMNmNNNmmNMNdNMM+.-..----.-:::.                          ````...:mh/NMMMNMMMNNMMh
// sMNNMMNMNNmyNMNdmNMo--.....                                  ``...---:dNMNMMNMMNNNMMN.
// :NNNMMMNNNsmMNmMNMy...`.-.`                                    `.-----:odNmmNMMMMMNMMo
// .NMMMmMMMNmMNNNNMm:-.```..                                       ``-----:/o//dMMMNMMMm
// .NMMMNMMNMMNMNNNNs--.``...                                         `....---..dMNMMMMM`
// .NNMMNNNNNMMMNNNN:-...`...                                          ```.....`+MMMMMMM.
// .MNNNNNNNMMMMMNNy.......-.`                                         ``..---.`.NMMMMMM`
// `NMNMMNNNMMNMMMm-...`.-----.`                                        ``.-----.`yMMMMMd
//  dMMMNNNNMMNNMMo`-....----..`          ``                      `.`` ```.------`:MMMMM-
//  /MMNMNNNMMNMMN-`.`..-.--.` `--..-:-.-.``..``               ```.-......--.----..NMMMd
//  `mMNMNNMMMNNMN.``...-.-../hddyysyhysyyso+--/::-..--...----:::+syyyyhhdddy+:-.-.hMMM:
//   :NNNNNNMMMMMN.`....--.:dy/:-.-/+++ososss+/:+shyo/::/:+os+:+syosyoso+/://ss//.`+MMm
//    +MdmNNMNMMMN+.--....:+-.-:+ooymdddmdhyo++ss+/yMo.`..oNsyhdhmdmmmmNmdo:-.--:+-:MM/
//   `y/..-+dNNMMMo-shhyo++--+sso-`dsymoso.smyso+//.od+/:/ho+yyhd/ymsNhyy./yy/``.-hhmm`
//   .s+md+- oMMMm``.-/sy//-.+/s.  odys+s-  /shyso+.sm+:::yd/hh+:`.hyyhy- `/y/.` `hs/s`
//   -oyMNyhs:NMMo     `.-`         .---` ``.`/::+s/ms````-mo+:`````.--` ````     `sNm`
//   `hsMh`.hymMM:       `-         `          .:+:hy`     od:-`                  .+sM-``
//    o+o/``-/mMM-        .-                ``.```hy`       s.`.`                 -/+M+``
//    .s `./NMMMM-         --            ````  `:ho`        .s`  ```             ./.+My`
//     /: `+MMdMM/          -.  `       `   ..+++-           :d/.             ``:o-`oMy
//      o. .sdNMMm`            `--:://+//.`-///:.           `.ohooo:-.`` `.-:+//:..`hMy
//      `s```.yMMMs                  ```     .y+  `::.:----.-``o:-::/:::--:::-----..mMo
//       :s` `oMNMN-                         :N+  -NNhy/:/sds./:..----------------`/MN
//         +o``-NMNMd`                      `-syyoo++/.++:so/+yN+..--....-..-....--`dM+
//         +:.`oMNNN`                     .:-` `.::.` `--..---/+/---.```........-.:d:
//          ./++Ny::`                   `--`          .--..-----::-..```......---.s.
//            `:os.--`                  .`            `.. ``.------.`.```..-----.:o
//              `h-..`                 ``        .:syy/-/ydho-.--...`````.------.+.
//               +o`.`                        ./ymNNNNNNNmmNNNh:....``.```.-----:s
//               `h-`.                    -/+oyo/:----:---.--:+sso:........--::-+:
//                /d...                 `.++:  -:--/+:/oo+o++-.``--.....-----:-:y
//                `Md:.`                ``     `-:/+ooooo+/-........-----------yo
//                 mNNs-`                     `..-/oo+://:/oo:......----------os
//                 h:+md:.                  ...``.`         `------.---------++
//                `h..-+ddo.`                            ``.----------------s:
//                 h` .--/ydy:`                   `...--------------------+y.
//                 h`   ..--+yds+.`               `....----------------:+dN`
//                `y      `.-.-:sdhs:.`    `...````..----------------:smsdm
//                `h         .--..-+ymdy+/:----:----------------.-/shs+.`os
//                `h           `..--..:sdmmhyo/::----------::/+syhy/....`+-
//                -y              `..--..--/oosyyyhhhyyyssoooo/:.`...`.` /-
//                `.                  `..--.......................````   +`
//                                       `...------..-.........``
//                                           ``..-.--........``
//                                                ```..```

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
    address public immutable usdcAddress;
    address public immutable balanceSheetAddress;
    address public immutable schoolAddress;
    address public treasuryAddress;

    bytes32 public constant DEFRAG_SYSTEM_ADMIN_ROLE =
        keccak256("DEFRAG_SYSTEM_ADMIN_ROLE");
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    bytes32 public constant ULP_ROLE = keccak256("ULP_ROLE");

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
    event Redeemed(address indexed _user, uint256 _amount);
    event SetTreasuryAddress(
        address indexed _operator,
        address _new,
        address _old
    );

    constructor(
        address _nftCollectionAddress,
        address _usdcAddress,
        address _balanceSheetAddress,
        address _treasuryAddress,
        address _schoolAddress
    ) {
        nftCollectionAddress = _nftCollectionAddress;
        usdcAddress = _usdcAddress;
        balanceSheetAddress = _balanceSheetAddress;
        treasuryAddress = _treasuryAddress;
        schoolAddress = _schoolAddress;

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
            IERC20Metadata(usdcAddress).balanceOf(address(this)) >=
                amountInUSDC(_amount),
            "AssetManager: not enough USDC"
        );

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _depositNFT(_tokenIds[i]);
        }

        IERC20Metadata(usdcAddress).transfer(msg.sender, amountInUSDC(_amount));
        IBalanceSheet(balanceSheetAddress).setLoan(
            msg.sender,
            _tokenIds,
            _amount
        );

        ISmolSchool(schoolAddress).joinStat(nftCollectionAddress, 0, _tokenIds);

        emit Borrowed(msg.sender, _tokenIds, _amount);
    }

    /**
     * @notice make a payment for the loan
     * @dev user must approve the ERC20 asset for transfer before
     * @param _amount amount of USDC
     */
    function makePayment(
        uint256 _amount,
        address _userAddress
    ) public nonReentrant whenNotPaused {
        require(
            IERC20Metadata(usdcAddress).balanceOf(address(msg.sender)) >=
                amountInUSDC(_amount),
            "AssetManager: not enough owned"
        );

        uint256 protocolFees = IBalanceSheet(balanceSheetAddress).setPayment(
            _userAddress,
            _amount
        );

        if (protocolFees > 0) {
            // move funds into AssetManager
            _transferUSDC(
                msg.sender,
                address(this),
                (amountInUSDC(_amount) - amountInUSDC(protocolFees))
            );

            // move protocol fee to treasury
            _transferUSDC(
                msg.sender,
                treasuryAddress,
                amountInUSDC(protocolFees)
            );

            emit SentToTreasuryAmount(treasuryAddress, protocolFees);
        } else {
            // move funds into AssetManager
            _transferUSDC(msg.sender, address(this), amountInUSDC(_amount));
        }

        emit PaidAmount(msg.sender, _userAddress, _amount);
    }

    /**
     * @notice withdraw collateral
     * @param _tokenIds - array of token ids
     */
    function withdrawCollateral(
        uint256[] memory _tokenIds
    ) public nonReentrant whenNotPaused {
        address user = msg.sender;

        ISmolSchool(schoolAddress).leaveStat(
            nftCollectionAddress,
            0,
            _tokenIds
        );

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
        // move the collateral to treasury
        uint256[] memory tokenIds = IBalanceSheet(balanceSheetAddress)
            .getTokenIds(_userAddress);

        ISmolSchool(schoolAddress).leaveStat(nftCollectionAddress, 0, tokenIds);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            IERC721(nftCollectionAddress).safeTransferFrom(
                address(this),
                treasuryAddress,
                tokenIds[i]
            );

            emit Liquidated(_userAddress, treasuryAddress, tokenIds[i]);
        }

        // set liquidation in balance sheet
        IBalanceSheet(balanceSheetAddress).setLiquidation(_userAddress);
    }

    /**
     * @notice redeem ERC20
     * @param _user - address
     * @param _amount - amount
     */
    function redeemERC20(address _user, uint256 _amount) public onlyULP {
        IERC20Metadata(usdcAddress).transfer(_user, _amount);
        emit Redeemed(_user, _amount);
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
     * @notice set treasury address
     * @param _treasuryAddress - address
     */
    function setTreasuryAddress(address _treasuryAddress) public onlyAdmin {
        emit SetTreasuryAddress(msg.sender, _treasuryAddress, treasuryAddress);
        treasuryAddress = _treasuryAddress;
    }

    /**
     * @notice helper to convert wei into USDC
     * @param _amount - 18 decimal amount
     * @return uint256 - USDC decimal compliant amount
     */
    function amountInUSDC(uint256 _amount) public view returns (uint256) {
        // because USDC is 6 decimals, we need to fix the decimals
        // https://docs.openzeppelin.com/contracts/4.x/erc20#a-note-on-decimals
        uint8 decimals = IERC20Metadata(usdcAddress).decimals();
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

    /**
     * @notice transfer the USDC
     * @param _from - address
     * @param _to - address
     * @param _amount - amount
     */
    function _transferUSDC(
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        IERC20Metadata(usdcAddress).transferFrom(_from, _to, _amount);
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

    modifier onlyULP() {
        require(hasRole(ULP_ROLE, msg.sender), "AssetManager: only ULP");
        _;
    }
}

