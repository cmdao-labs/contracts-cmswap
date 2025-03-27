// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mintable is ERC20 {
    constructor (
        string memory _tokenName,
        string memory _tokenSymbol,
        address _mintTo
    ) ERC20(_tokenName, _tokenSymbol) {
        _mint(_mintTo, 1_000_000_000 ether);
    }
}
