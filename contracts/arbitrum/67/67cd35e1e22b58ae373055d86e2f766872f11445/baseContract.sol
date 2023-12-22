// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./DBContract.sol";
import "./AddressUpgradeable.sol";
import "./ContextUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IUser.sol";
// Uncomment this line to use console.log
// import "hardhat/console.sol";

abstract contract baseContract is ContextUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address constant public BLACK_HOLE = address(0xdead);
    address immutable public DB_CONTRACT;

    constructor(address dbContract) {
        DB_CONTRACT = dbContract;
    }

    modifier onlyLYNKNFTOrDBContract() {
        require(
            DBContract(DB_CONTRACT).LYNKNFT() == _msgSender() ||
            DB_CONTRACT == _msgSender(),
                'baseContract: caller not the LYNK NFT contract.'
        );
        _;
    }

    modifier onlyLYNKNFTContract() {
        require(DBContract(DB_CONTRACT).LYNKNFT() == _msgSender(), 'baseContract: caller not the LYNK NFT contract.');
        _;
    }

    modifier onlyUserContract() {
        require(DBContract(DB_CONTRACT).USER_INFO() == _msgSender(), 'baseContract: caller not the User contract.');
        _;
    }

    modifier onlyStakingContract() {
        require(DBContract(DB_CONTRACT).STAKING() == _msgSender(), 'baseContract: caller not the Staking contract.');
        _;
    }

    modifier onlyUserOrStakingContract() {
        require(
            DBContract(DB_CONTRACT).USER_INFO() == _msgSender() ||
            DBContract(DB_CONTRACT).STAKING() == _msgSender(),
                'baseContract: caller not the User OR Staking contract.'
        );
        _;
    }

    function __baseContract_init() internal {
        __Context_init();
    }

    function _pay(address _payment, address _payer, uint256 _amount ,IUser.REV_TYPE _type) internal {
        address target = DBContract(DB_CONTRACT).revADDR(uint256(_type));
        if (address(0) == _payment) {
            require(msg.value == _amount, 'baseContract: invalid value.');
            AddressUpgradeable.sendValue(payable(target), _amount);
            return;
        }

        require(
            IERC20Upgradeable(_payment).allowance(_payer, address(this)) >= _amount,
            'baseContract: insufficient allowance'
        );

        IERC20Upgradeable(_payment).safeTransferFrom(_payer, target, _amount);

    }
    /**
     * @dev Throws if called by any account other than the operator.
     */
    modifier onlyOperator() {
        require( DBContract(DB_CONTRACT).operator() == _msgSender(), "baseContract: caller is not the operator");
        _;
    }

}

