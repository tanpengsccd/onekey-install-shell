// api/handler.js
import fetch from "node-fetch"

export default async function handler(req, res) {
    const {url} = req
    const path = url.slice(1) // 去掉前面的'/'

    // 如果路径为空，重定向到 www + 请求的host
    if (!path) {
        const newUrl = `https://www.${req.headers.host}`
        res.writeHead(302, {Location: newUrl})
        res.end()
        return
    }

    // 构建新的URL，指向GitHub上的资源
    const githubUrl = `https://raw.githubusercontent.com/tanpengsccd/onekey-install-shell/master/${path}`

    try {
        // 尝试从GitHub获取内容
        const response = await fetch(githubUrl)

        // 检查GitHub的响应是否成功
        if (!response.ok) {
            throw new Error("GitHub resource not found")
        }

        // 获取 GitHub 的响应数据
        const data = await response.text()

        // 添加允许跨域访问的响应头
        res.setHeader("Access-Control-Allow-Origin", "*")
        res.status(200).send(data)
    } catch (error) {
        // 如果从GitHub获取内容失败，返回自定义的404错误
        res.status(404).send("没有找到 https://github.com/tanpengsccd/onekey-install-shell 中的脚本，请检查URL路径")
    }
}
