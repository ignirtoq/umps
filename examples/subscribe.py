from asyncio import CancelledError, Queue, get_event_loop
from functools import partial
from ipaddress import IPv4Network
from umps import Interface


def notify(queue: Queue, topic: str, message: bytes):
    queue.put_nowait((topic, message))


async def single_subscribe(network: IPv4Network, port: int, topic: str):
    queue = Queue()
    interface = Interface(network, port, timeout=0.1)
    await interface.subscribe(topic, partial(notify, queue))
    while True:
        try:
            topic, message = await queue.get()
        except CancelledError:
            break
        else:
            print(f"Received '{topic}' message: {message!r}")
    await interface.terminate()


if __name__ == '__main__':
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument('-t', '--topic', help='message topic',
                   default='greeting')
    p.add_argument('-n', '--network', default='239.11.122.0/24',
                   help='multicast network (e.g. 239.1.0.0/16)')
    p.add_argument('-p', '--port', type=int, help='port (default: %(default)d)',
                   default=50123)

    args = p.parse_args()
    network = IPv4Network(args.network)

    loop = get_event_loop()
    future = loop.create_task(single_subscribe(network, args.port, args.topic))
    try:
        loop.run_until_complete(future)
    except KeyboardInterrupt:
        future.cancel()
        loop.run_until_complete(future)
    loop.close()
