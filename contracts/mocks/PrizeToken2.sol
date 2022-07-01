// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PrizeToken2 is ERC20, Ownable {
    constructor(address _owner) ERC20("PrizeToken2", "PrizeToken2") {
        transferOwnership(_owner);
        _mint(_owner, 10000 * 10**18);
    }
}
