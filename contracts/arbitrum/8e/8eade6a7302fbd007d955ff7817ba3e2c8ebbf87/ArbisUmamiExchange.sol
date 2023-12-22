//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//                                                                            //
//                              #@@@@@@@@@@@@&,                               //
//                      .@@@@@   .@@@@@@@@@@@@@@@@@@@*                        //
//                  %@@@,    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    //
//               @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                 //
//             @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@               //
//           *@@@#    .@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@             //
//          *@@@%    &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            //
//          @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//                                                                            //
//          (@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@,           //
//          (@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@,           //
//                                                                            //
//               @@   @@     @   @       @       @   @       @                //
//               @@   @@    @@@ @@@     @_@     @@@ @@@     @@@               //
//                &@@@@   @@  @@  @@  @@ ^ @@  @@  @@  @@   @@@               //
//                                                                            //
//          @@@@@      @@@%    *@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//          @@@@@      @@@@    %@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//          .@@@@      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            //
//            @@@@@  &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@             //
//                (&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&(                 //
//                                                                            //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

// Dependancies
import { IERC20 } from "./IERC20.sol";
import { AccessControl } from "./AccessControl.sol";
import { SafeMath } from "./SafeMath.sol";
import { SafeERC20 } from "./SafeERC20.sol";

/**
 * @title Arbis Umami Exchange
 * @author EncryptedBunny
 * @dev Exchange Arbis for Umami at a fixed rate. Arbis will be burnt. 
 */

contract ArbisUmamiExchange is AccessControl {

    /************************************************
     *  LIBRARIES
     ***********************************************/
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /************************************************
     *  EVENTS
     ***********************************************/
    event Exchanged(uint256 arbisAmountIn, uint256 umamiAmountOut, address sender);

    /************************************************
     *  STORAGE
     ***********************************************/

    IERC20 public arbis;
    IERC20 public umami;

    uint256 public rate;
    address public burnAddress;
    bool public active;

    uint256 public constant ARBIS_UNIT = 1000000000000000000;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

     /************************************************
     *  CONSTRUCTOR
     ***********************************************/

    /**
     * @param _arbis Address of the Arbis token
     * @param _umami Address of the Umami token
     * @param _rate Rate of Umami per arbis. should be number of umami per arbis multiplied by 10^9
     */
    constructor(
        address _arbis,
        address _umami,
        uint256 _rate
    ) {
        require(_arbis != address(0), "arbis address cannot be 0");
        require(_umami != address(0), "umami address cannot be 0");

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        arbis = IERC20(_arbis);
        umami = IERC20(_umami);
        burnAddress = 0x000000000000000000000000000000000000dEaD;
        rate = _rate;

        active = true;
    }

    /************************************************
     *  FUNCTIONS
     ***********************************************/

    /**
     * @dev The exchanging function to call.
     */
    function exchange(uint _arbisAmount) public {

        require(active, "Exchange not active");
        require(_arbisAmount > 0, "Arbis is 0");

        uint256 umamiAmount = exchangeAmount(_arbisAmount);

        require(umamiAmount > 0, "Umami is 0");
        require(umamiAmount < umami.balanceOf(address(this)), "Not enough Umami");

        burn(_arbisAmount);

        umami.safeTransfer(msg.sender, umamiAmount);
        
        emit Exchanged(_arbisAmount, umamiAmount, msg.sender);
    }

    /**
     * @dev Burn the arbis.
     */
    function burn(uint _arbisAmount) private {

        require(_arbisAmount > 0, "Arbis is 0");
        arbis.safeTransferFrom(msg.sender, burnAddress, _arbisAmount);
        
    }

    /************************************************
     *  VIEWS
     ***********************************************/

    /**
     * @dev Return the amount of umami that will be recieved from arbis amount.
     * @notice  umami 9 decimals
     *          arbis 18 decimals
     *          (rate / 10^18) * arbis = umami
     */
    function exchangeAmount(uint _arbisAmount) public view returns (uint256) {
        uint256 umamiReturned = rate.mul(_arbisAmount).div(ARBIS_UNIT);

        return umamiReturned;
    }

    /************************************************
     *  MUTABLES
     ***********************************************/

    /**
     * @dev Change the rate of exchange.
     * @notice rate should be number of umami per arbis multiplied by 10^9 
     */
    function changeRate(uint256 _rate) external onlyAdmin {
        rate = _rate;
    }

    /**
     * @dev Change the address arbis is burned too.
     */
    function changeBurnAddress(address _burnAddress) external onlyAdmin {
        burnAddress = _burnAddress;   
    }

    /**
     * @dev Change active to switch on or off exchanger.
     */
    function switchActive(bool _active) external onlyAdmin {
        active = _active;
    }

    /************************************************
     *  ADMIN
     ***********************************************/

     /**
     * @dev Recover a erc20 token.
     */
    function recoverToken(address tokenAddress) external onlyAdmin {
        IERC20 token = IERC20(tokenAddress);

        uint256 balance = token.balanceOf(address(this));

        token.safeTransfer(msg.sender, balance);
    }

    /**
     * @notice recover eth
     */
    function recoverEth() external onlyAdmin {
        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Withdraw failed");
    }

    /**
     * @dev Access control.
     */
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }
}

