// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./baseContract.sol";
import "./IUser.sol";
import "./IERC20Mintable.sol";
import "./OwnableUpgradeable.sol";
import "./draft-ERC20PermitUpgradeable.sol";
// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract APToken is ERC20PermitUpgradeable, baseContract, IERC20Mintable {

    event MintAP(address indexed user, uint256 amountIn, uint256 amountOut);

    constructor(address dbAddress) baseContract(dbAddress) { }

    function __APToken_init() public initializer {
        __APToken_init_unchained();
        __ERC20Permit_init("Attribute Point");
        __ERC20_init("Attribute Point", "AP ");
        __baseContract_init();
    }

    function __APToken_init_unchained() private {

    }

    function mint(uint256 _indexPackage) external{
        require(
            IUser(DBContract(DB_CONTRACT).USER_INFO()).isValidUser(_msgSender()),
                'APToken: not a valid user.'
        );

        uint256[] memory package = DBContract(DB_CONTRACT).packageByIndex(_indexPackage);
        // only settle if length eq 3. {@link DBContract#setSellingPackage}
        // require(package.length == 3, 'APToken: unrecognized package.');

        _pay(address(uint160(package[0])), _msgSender(), package[1],IUser.REV_TYPE.LYNK_ADDR);
        _mint(_msgSender(), package[2]);

        emit MintAP(_msgSender(),package[1],package[2]);
    }

    function mint(address account, uint256 amount) external onlyUserContract {
        _mint(account, amount);
    }

    function _beforeTokenTransfer (address from,address to,uint256 )internal virtual override
    {

        // if(from == address(0)){
        //     return ;
        // }
        // if(DBContract(DB_CONTRACT).isRevAddr(from) ||DBContract(DB_CONTRACT).isRevAddr(to)){
        //     return ;
        // }

        // require(false,"can token can not transfer");
    }

}

