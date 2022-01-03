from scripts.helper import get_account, fund_with_link, get_account2
from scripts.deploy import approve_erc20
from brownie import (
    DegenDojo,
    DojoHouse,
    DojoBar,
    network,
    config,
    DojoRouter,
    interface,
)
from web3 import Web3
import yaml
import json
import os
import shutil
import time

SLIPPAGE = 5


def check_amount(
    token_in,
    token_out,
):
    dojo_router = DojoRouter[-1]
    out = dojo_router.getAmountOut(0.6 * (10 ** 18), token_out, token_in)
    print(out)
    return out


def router_trade_tokens(out):
    account = get_account()
    dojo_router = DojoRouter[-1]

    deadline = time.time() + 10000

    # Min amount of ETH to get out
    token_in = config["networks"][network.show_active()]["link_token"]
    token_out = config["networks"][network.show_active()]["weth"]
    minOut = (dojo_router.getAmountOut(out, token_out, token_in)) * (
        (100 - SLIPPAGE) / 100
    )
    print("min out: ", minOut)

    tx1 = approve_erc20(
        out * 2,
        dojo_router,
        config["networks"][network.show_active()]["link_token"],
        account,
    )
    tx1.wait(1)
    dojo_router.swapTokensForETH(
        out,
        config["networks"][network.show_active()]["link_token"],
        1,
        minOut,
        deadline,
        {"from": account},
    )


def router_trade_eth():
    account = get_account()
    dojo_router = DojoRouter[-1]
    dojo_router.swapETHforTokens(
        1,
        config["networks"][network.show_active()]["link_token"],
        {"from": account, "value": 0.1 * 10 ** 18},
    )


def claim_tokens():
    account = get_account()
    dojo_router = DojoRouter[-1]
    dojo_router.claimETHTrade({"from": account})


def main():
    token_in = config["networks"][network.show_active()]["weth"]
    token_out = config["networks"][network.show_active()]["link_token"]
    out = check_amount(token_in, token_out)
    router_trade_tokens(out)
