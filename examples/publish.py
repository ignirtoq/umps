from asyncio import get_event_loop
from ipaddress import IPv4Network
from umps import Interface


async def single_publish(network: IPv4Network, port: int, topic: str,
                         message: bytes):
    interface = Interface(network, port)
    print(f"Publishing '{topic}' message: {message!r}")
    await interface.publish(topic, message)
    await interface.terminate()


if __name__ == '__main__':
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument('-t', '--topic', help='message topic',
                   default='greeting')
    p.add_argument('-m', '--message', help='message body',
                   default='hello, world!')
    p.add_argument('-n', '--network', default='239.11.122.0/24',
                   help='multicast network (e.g. 239.1.0.0/16)')
    p.add_argument('-p', '--port', type=int, help='port (default: %(default)d)',
                   default=50123)

    args = p.parse_args()
    network = IPv4Network(args.network)

    loop = get_event_loop()
    loop.run_until_complete(single_publish(network, args.port, args.topic,
                                           args.message))
