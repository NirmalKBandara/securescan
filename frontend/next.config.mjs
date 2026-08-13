/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  experimental: {
    useTypeScriptCli: false,
  },
  async rewrites() {
    const apiOrigin = process.env.BALLERINA_API_BASE_URL?.replace(/\/$/, "") || "http://127.0.0.1:9090";
    return [{ source: "/backend/:path*", destination: `${apiOrigin}/:path*` }];
  },
};

export default nextConfig;
