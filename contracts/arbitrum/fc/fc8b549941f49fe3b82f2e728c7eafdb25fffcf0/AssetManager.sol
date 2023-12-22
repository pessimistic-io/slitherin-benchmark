// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./AccessControlUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20Metadata.sol";
import {IBalanceSheet} from "./IBalanceSheet.sol";
import {IAssetManager} from "./IAssetManager.sol";

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

/// @title Asset Manager is in charge of moving and holding assets such as ERC20s
/// @author DeFragDAO
/// @custom:experimental This is an experimental contract
contract AssetManager is
    IAssetManager,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    IERC20Metadata public collateralToken;
    IERC20Metadata public usdc;
    IBalanceSheet public balanceSheet;
    address public treasuryAddress;

    uint256 public totalProtocolFeesPaid;

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
        uint256 _amount
    );
    event Borrowed(
        address indexed _user,
        uint256 _depositAmount,
        uint256 _borrowAmount
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
    event Liquidated(address indexed _user, address _to, uint256 _amount);
    event Redeemed(address indexed _user, uint256 _amount);
    event SetTreasuryAddress(
        address indexed _operator,
        address _new,
        address _old
    );
    event ProtocolFeePaid(
        address _treasuryAddress,
        address _user,
        uint256 _amount
    );

    // FOR UPGRADES
    event BorrowedForUser(
        address indexed _user,
        uint256 _depositAmount,
        uint256 _borrowAmount,
        address _operator
    );
    event MovedCollateral(
        address indexed _user,
        address _to,
        uint256 _collateralAmount
    );
    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");

    function initialize(
        address _collateralTokenAddress,
        address _usdcAddress,
        address _balanceSheetAddress,
        address _treasuryAddress
    ) external initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();
        __Pausable_init();

        collateralToken = IERC20Metadata(_collateralTokenAddress);
        usdc = IERC20Metadata(_usdcAddress);
        balanceSheet = IBalanceSheet(_balanceSheetAddress);
        treasuryAddress = _treasuryAddress;

        _pause();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice borrow and deposit collateral
     * @dev user must approve the ERC20 asset for transfer before
     * @param _depositAmount - amount to be deposited
     * @param _borrowAmount - amount to be borrowed
     */
    function borrow(
        uint256 _depositAmount,
        uint256 _borrowAmount
    ) public nonReentrant whenNotPaused {
        // check if there are enough stable coins to lend
        require(
            usdc.balanceOf(address(this)) >= amountInUSDC(_borrowAmount),
            "AssetManager: not enough USDC"
        );

        collateralToken.transferFrom(msg.sender, address(this), _depositAmount);
        usdc.transfer(msg.sender, amountInUSDC(_borrowAmount));

        balanceSheet.setLoan(msg.sender, _depositAmount, _borrowAmount);

        emit Borrowed(msg.sender, _depositAmount, _borrowAmount);
    }

    /**
     * @notice borrow for user and deposit collateral
     * @dev strategist must approve the ERC20 asset before transfer
     * @param _depositAmount - amount to be deposited
     * @param _borrowAmount - amount to be borrowed
     * @param _userAddress - address of the user
     */
    function borrowForUser(
        uint256 _depositAmount,
        uint256 _borrowAmount,
        address _userAddress
    ) public nonReentrant whenNotPaused onlyStrategist {
        // check if there are enough stable coins to lend
        require(
            usdc.balanceOf(address(this)) >= amountInUSDC(_borrowAmount),
            "AssetManager: not enough USDC"
        );

        collateralToken.transferFrom(msg.sender, address(this), _depositAmount);
        usdc.transfer(msg.sender, amountInUSDC(_borrowAmount));

        balanceSheet.setLoan(_userAddress, _depositAmount, _borrowAmount);

        emit BorrowedForUser(
            _userAddress,
            _depositAmount,
            _borrowAmount,
            msg.sender
        );
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
            usdc.balanceOf(address(msg.sender)) >= amountInUSDC(_amount),
            "AssetManager: not enough owned"
        );

        uint256 protocolFees = balanceSheet.setPayment(_userAddress, _amount);

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

            totalProtocolFeesPaid += protocolFees;
            emit ProtocolFeePaid(treasuryAddress, _userAddress, protocolFees);
        } else {
            // move funds into AssetManager
            _transferUSDC(msg.sender, address(this), amountInUSDC(_amount));
        }

        emit PaidAmount(msg.sender, _userAddress, _amount);
    }

    /**
     * @notice withdraw collateral
     * @param _amount - amount to be withdrawn
     */
    function withdrawCollateral(
        uint256 _amount
    ) public nonReentrant whenNotPaused {
        balanceSheet.removeCollateral(msg.sender, _amount);

        collateralToken.transfer(msg.sender, _amount);

        emit WithdrewCollateral(msg.sender, address(this), _amount);
    }

    /**
     * @notice liqudate the user - move tokens to treasury and null out the loan in balance sheet
     * @param _userAddress - address of the user
     */
    function liquidate(
        address _userAddress
    ) public nonReentrant onlyLiquidator returns (uint256 _transferedAmount) {
        // move the collateral to liquidator
        uint256 collateralAmount = balanceSheet.getCollateralAmount(
            _userAddress
        );

        collateralToken.transfer(msg.sender, collateralAmount);

        // set liquidation in balance sheet
        balanceSheet.setLiquidation(_userAddress);

        emit Liquidated(_userAddress, msg.sender, collateralAmount);

        return collateralAmount;
    }

    /**
     * @notice close the position - move tokens to strategist
     * @param _userAddress - address of the user
     */
    function moveCollateral(
        address _userAddress,
        uint256 _amount
    ) public nonReentrant whenNotPaused onlyStrategist {
        // move the collateral to strategist
        require(
            balanceSheet.getCollateralAmount(_userAddress) >= _amount,
            "AssetManager: not enough collateral"
        );

        collateralToken.transfer(msg.sender, _amount);
        emit MovedCollateral(_userAddress, msg.sender, _amount);
    }

    /**
     * @notice remove collateral for user
     * @param _userAddress - address of the user
     * @param _amount - amount to be removed
     */
    function removeCollateralForUser(
        address _userAddress,
        uint256 _amount
    ) public nonReentrant onlyStrategist {
        balanceSheet.removeCollateral(_userAddress, _amount);
    }

    /**
     * @notice redeem ERC20
     * @param _user - address
     * @param _amount - amount
     */
    function redeemERC20(
        address _user,
        uint256 _amount
    ) public nonReentrant onlyULP {
        usdc.transfer(_user, _amount);
        emit Redeemed(_user, _amount);
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
    function withdrawEth(
        address _to,
        uint256 _amount
    ) public nonReentrant onlyAdmin {
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
    ) public nonReentrant onlyAdmin {
        IERC20Metadata(_tokenAddress).transfer(_to, _amount);
        emit WithdrewERC20(msg.sender, _to, _amount, _tokenAddress);
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
        uint8 decimals = usdc.decimals();
        return (_amount / 10 ** (18 - decimals));
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
        IERC20Metadata(usdc).transferFrom(_from, _to, _amount);
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

    modifier onlyStrategist() {
        require(
            hasRole(STRATEGIST_ROLE, msg.sender),
            "AssetManager: only Strategist"
        );
        _;
    }
}

